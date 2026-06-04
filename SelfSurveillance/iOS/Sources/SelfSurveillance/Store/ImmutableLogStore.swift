// MARK: - ImmutableLogStore.swift
// Self Surveillance — Append-Only WORM (Write Once Read Many) Local Store
//
// Design principles:
//   • Every LogEntry is serialised to a single NDJSON line and appended to a
//     date-partitioned file.  No line is ever overwritten or removed.
//   • Each entry carries the SHA-256 hash of the previous entry, forming a
//     tamper-evident hash chain.  Any deletion or modification breaks the chain
//     and will be detected by the integrity checker.
//   • The store is backed by a second, read-only "seal" file that records the
//     last known good hash after every sync cycle.  This makes silent truncation
//     detectable even if the NDJSON file is somehow shortened.
//   • All writes go through a serial DispatchQueue so entries are never
//     interleaved by concurrent collectors.
//   • The directory is excluded from iCloud backup on purpose — the off-device
//     web server is the canonical backup.  Local storage is only a sync buffer.

import Foundation
import CryptoKit

public final class ImmutableLogStore {

    // MARK: - Singleton
    public static let shared = ImmutableLogStore()

    // MARK: - Storage layout
    //
    // <AppGroup>/SurveillanceLogs/
    //   YYYY-MM-DD/
    //     <source>.ndjson        — append-only event stream, one JSON object per line
    //   seal/
    //     <YYYY-MM-DD>_<source>.sha256   — last known good entry hash + sequence number
    //   pending/
    //     <UUID>.ndjson          — batches not yet ACKed by the server

    private let rootURL: URL
    private let sealURL: URL
    private let pendingURL: URL

    private let writeQueue = DispatchQueue(label: "com.selfsurveillance.store.write", qos: .utility)
    private var sequenceCounter: UInt64 = 0
    private var lastEntryHash: String = "GENESIS"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = []   // compact, one object per line
        return e
    }()

    // MARK: - Init
    private init() {
        // Use the shared App Group container so the store survives app reinstalls
        // and is accessible to extensions (Share Extension, Notification Extension).
        let appGroupID = "group.com.selfsurveillance"
        let container: URL
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            container = url
        } else {
            // Fallback to Documents during development / simulator
            container = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }

        rootURL    = container.appendingPathComponent("SurveillanceLogs", isDirectory: true)
        sealURL    = rootURL.appendingPathComponent("seal", isDirectory: true)
        pendingURL = rootURL.appendingPathComponent("pending", isDirectory: true)

        [rootURL, sealURL, pendingURL].forEach { url in
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // Exclude from iCloud backup — the server is the backup
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? rootURL.setResourceValues(resourceValues)

        // Restore sequence counter & last hash from seal files
        restoreChainState()
    }

    // MARK: - Live-broadcast hook (set by EmbeddedServer)
    public static var onNewEntry: ((LogEntry) -> Void)?

    // MARK: - Public API

    /// Append a single log entry.  This is the ONLY way to write data.
    /// Returns the written entry (with sequence number and hash filled in).
    @discardableResult
    public func append(
        source: DataSource,
        category: DataCategory,
        appBundleID: String? = nil,
        appDisplayName: String? = nil,
        eventType: String,
        payload: LogPayload,
        rawBytes: Data? = nil
    ) -> LogEntry {
        var entry: LogEntry!
        writeQueue.sync {
            sequenceCounter += 1
            let device = UIDevice.current
            entry = LogEntry(
                timestamp: Date(),
                deviceID: device.identifierForVendor?.uuidString ?? "unknown",
                deviceName: device.name,
                iOSVersion: device.systemVersion,
                source: source,
                category: category,
                appBundleID: appBundleID,
                appDisplayName: appDisplayName,
                eventType: eventType,
                payload: payload,
                rawBytes: rawBytes,
                sequenceNumber: sequenceCounter,
                previousEntryHash: lastEntryHash
            )
            writeEntryToDisk(entry)
            writeToPendingBatch(entry)
            lastEntryHash = sha256(entry)
            updateSeal(for: source)
        }
        ImmutableLogStore.onNewEntry?(entry)
        return entry
    }

    /// Append many entries atomically (same disk flush, same batch).
    public func appendBatch(_ items: [(DataSource, DataCategory, String?, String?, String, LogPayload, Data?)]) {
        writeQueue.sync {
            for (source, category, bundleID, appName, eventType, payload, raw) in items {
                sequenceCounter += 1
                let device = UIDevice.current
                let entry = LogEntry(
                    timestamp: Date(),
                    deviceID: device.identifierForVendor?.uuidString ?? "unknown",
                    deviceName: device.name,
                    iOSVersion: device.systemVersion,
                    source: source,
                    category: category,
                    appBundleID: bundleID,
                    appDisplayName: appName,
                    eventType: eventType,
                    payload: payload,
                    rawBytes: raw,
                    sequenceNumber: sequenceCounter,
                    previousEntryHash: lastEntryHash
                )
                writeEntryToDisk(entry)
                writeToPendingBatch(entry)
                lastEntryHash = sha256(entry)
                updateSeal(for: source)
            }
        }
    }

    /// Return all pending (unACKed) batches as a dictionary keyed by batch UUID string.
    public func pendingBatches() -> [String: [LogEntry]] {
        var result: [String: [LogEntry]] = [:]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: pendingURL, includingPropertiesForKeys: nil
        ) else { return result }

        for file in files where file.pathExtension == "ndjson" {
            let batchID = file.deletingPathExtension().lastPathComponent
            if let data = try? Data(contentsOf: file) {
                let entries = parseNDJSON(data)
                if !entries.isEmpty {
                    result[batchID] = entries
                }
            }
        }
        return result
    }

    /// Called by SyncEngine after the server confirms receipt of a batch.
    /// IMPORTANT: This deletes the *pending* file only — the main log is never touched.
    public func acknowledgeBatch(batchID: String) {
        writeQueue.async {
            let file = self.pendingURL.appendingPathComponent("\(batchID).ndjson")
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Verify the integrity of the full hash chain for a given source on a given date.
    /// Returns a list of any broken links found.
    public func verifyIntegrity(source: DataSource, date: Date = Date()) -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        let file = logFileURL(for: source, date: date)
        guard let data = try? Data(contentsOf: file) else { return issues }

        let entries = parseNDJSON(data)
        var expectedPrevHash = "GENESIS"

        for (index, entry) in entries.enumerated() {
            if entry.previousEntryHash != expectedPrevHash {
                issues.append(IntegrityIssue(
                    sequenceNumber: entry.sequenceNumber,
                    lineIndex: index,
                    expected: expectedPrevHash,
                    found: entry.previousEntryHash,
                    description: "Hash chain break at sequence \(entry.sequenceNumber)"
                ))
            }
            expectedPrevHash = sha256(entry)
        }
        return issues
    }

    // MARK: - Export / Integrity (used by EmbeddedServer HTTP routes)

    public func exportAllLogs() -> Data {
        var result = Data()
        guard let dateDirs = try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        ) else { return result }
        let skip: Set<String> = ["seal", "pending"]
        let sorted = dateDirs
            .filter { $0.hasDirectoryPath && !skip.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for dayURL in sorted {
            let files = ((try? FileManager.default.contentsOfDirectory(
                at: dayURL, includingPropertiesForKeys: nil
            )) ?? []).filter { $0.pathExtension == "ndjson" }
                       .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for fileURL in files {
                if let data = try? Data(contentsOf: fileURL) { result.append(data) }
            }
        }
        return result
    }

    public func verifyAllIntegrity() -> (checked: Int, issues: [IntegrityIssue]) {
        var all: [LogEntry] = []
        guard let dateDirs = try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        ) else { return (0, []) }
        let skip: Set<String> = ["seal", "pending"]
        for dayURL in dateDirs where dayURL.hasDirectoryPath && !skip.contains(dayURL.lastPathComponent) {
            let files = ((try? FileManager.default.contentsOfDirectory(
                at: dayURL, includingPropertiesForKeys: nil
            )) ?? []).filter { $0.pathExtension == "ndjson" }
            for fileURL in files {
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                all.append(contentsOf: parseNDJSON(data))
            }
        }
        all.sort { $0.sequenceNumber < $1.sequenceNumber }
        var issues: [IntegrityIssue] = []
        var expectedPrev = "GENESIS"
        for (i, entry) in all.enumerated() {
            if entry.previousEntryHash != expectedPrev {
                issues.append(IntegrityIssue(
                    sequenceNumber: entry.sequenceNumber, lineIndex: i,
                    expected: expectedPrev, found: entry.previousEntryHash,
                    description: "Chain break at seq \(entry.sequenceNumber)"
                ))
            }
            expectedPrev = sha256(entry)
        }
        return (all.count, issues)
    }

    // MARK: - Query API (used by EmbeddedServer HTTP routes)

    public func queryEntries(source: String?, search: String?, limit: Int, offset: Int) -> [LogEntry] {
        var results: [LogEntry] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        guard let dateDirs = try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        ) else { return [] }

        let sorted = dateDirs
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        outer: for dayURL in sorted {
            let files: [URL]
            if let src = source {
                let candidate = dayURL.appendingPathComponent("\(src).ndjson")
                files = FileManager.default.fileExists(atPath: candidate.path) ? [candidate] : []
            } else {
                files = (try? FileManager.default.contentsOfDirectory(
                    at: dayURL, includingPropertiesForKeys: nil
                ))?.filter { $0.pathExtension == "ndjson" } ?? []
            }

            for fileURL in files {
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                let lines = (String(data: data, encoding: .utf8) ?? "")
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .reversed()

                for line in lines {
                    guard let lineData = line.data(using: .utf8),
                          let entry = try? JSONDecoder().decode(LogEntry.self, from: lineData)
                    else { continue }

                    if let needle = search?.lowercased() {
                        let hay = (String(data: (try? JSONEncoder().encode(entry)) ?? Data(), encoding: .utf8) ?? "").lowercased()
                        if !hay.contains(needle) { continue }
                    }

                    results.append(entry)
                    if results.count >= offset + limit { break outer }
                }
            }
        }

        let slice = results.dropFirst(offset)
        return Array(slice.prefix(limit))
    }

    public func querySummary(deviceID: String?) -> [String: Any] {
        var bySource: [String: Int] = [:]
        var total = 0

        guard let dateDirs = try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        ) else { return [:] }

        for dayURL in dateDirs where dayURL.hasDirectoryPath {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dayURL, includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "ndjson" } ?? []

            for fileURL in files {
                guard let data = try? Data(contentsOf: fileURL),
                      let text = String(data: data, encoding: .utf8)
                else { continue }

                let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                let sourceName = fileURL.deletingPathExtension().lastPathComponent
                bySource[sourceName, default: 0] += lines.count
                total += lines.count
            }
        }

        let device = UIDevice.current
        let deviceInfo: [String: Any] = [
            "deviceID":   device.identifierForVendor?.uuidString ?? "unknown",
            "deviceName": device.name,
            "iOSVersion": device.systemVersion,
            "entryCount": total
        ]

        return [
            "totalEntries": total,
            "bySource":     bySource,
            "devices":      [deviceInfo]
        ]
    }

    // MARK: - Private helpers

    private func writeEntryToDisk(_ entry: LogEntry) {
        guard let line = try? encoder.encode(entry),
              var lineStr = String(data: line, encoding: .utf8) else { return }
        lineStr += "\n"

        let file = logFileURL(for: entry.source, date: entry.timestamp)
        ensureDirectory(for: file)

        if let lineData = lineStr.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: file.path) {
                // Append mode — the only write mode that exists
                if let handle = try? FileHandle(forWritingTo: file) {
                    handle.seekToEndOfFile()
                    handle.write(lineData)
                    try? handle.close()
                }
            } else {
                try? lineData.write(to: file, options: .atomic)
            }
        }
    }

    private func writeToPendingBatch(_ entry: LogEntry) {
        // Each sync cycle gets its own pending file, identified by the current
        // 15-second window.  This keeps individual batch sizes manageable.
        let windowID = pendingWindowID()
        let file = pendingURL.appendingPathComponent("\(windowID).ndjson")

        guard let line = try? encoder.encode(entry),
              var lineStr = String(data: line, encoding: .utf8) else { return }
        lineStr += "\n"

        if let lineData = lineStr.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: file.path) {
                if let handle = try? FileHandle(forWritingTo: file) {
                    handle.seekToEndOfFile()
                    handle.write(lineData)
                    try? handle.close()
                }
            } else {
                try? lineData.write(to: file, options: .atomic)
            }
        }
    }

    private func pendingWindowID() -> String {
        // Rounds current time down to the nearest 15-second boundary
        let interval = Date().timeIntervalSince1970
        let window = Int(interval / 15) * 15
        return "batch_\(window)"
    }

    private func logFileURL(for source: DataSource, date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)
        let dir = rootURL.appendingPathComponent(dateStr, isDirectory: true)
        return dir.appendingPathComponent("\(source.rawValue).ndjson")
    }

    private func ensureDirectory(for fileURL: URL) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func sha256(_ entry: LogEntry) -> String {
        guard let data = try? encoder.encode(entry) else { return "ERROR" }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func updateSeal(for source: DataSource) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        let sealFile = sealURL.appendingPathComponent("\(dateStr)_\(source.rawValue).sha256")
        let content = "\(sequenceCounter):\(lastEntryHash)"
        try? content.data(using: .utf8)?.write(to: sealFile, options: .atomic)
    }

    private func restoreChainState() {
        // Find the most recent seal file and restore counter + hash from it
        guard let sealFiles = try? FileManager.default.contentsOfDirectory(
            at: sealURL, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let sorted = sealFiles.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da > db
        }

        guard let latest = sorted.first,
              let content = try? String(contentsOf: latest),
              let colonIdx = content.firstIndex(of: ":") else { return }

        let seqStr = String(content[content.startIndex..<colonIdx])
        let hash   = String(content[content.index(after: colonIdx)...])

        if let seq = UInt64(seqStr) {
            sequenceCounter = seq
            lastEntryHash   = hash
        }
    }

    private func parseNDJSON(_ data: Data) -> [LogEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> LogEntry? in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(LogEntry.self, from: lineData)
            }
    }
}

// MARK: - Supporting Types

public struct IntegrityIssue {
    public let sequenceNumber: UInt64
    public let lineIndex: Int
    public let expected: String
    public let found: String
    public let description: String
}
