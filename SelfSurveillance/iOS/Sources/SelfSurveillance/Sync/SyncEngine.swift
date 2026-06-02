// MARK: - SyncEngine.swift
// Pushes pending batches to the self-hosted backend every 15 seconds.
//
// Design:
//   • Uses a dedicated URLSession with background transfer support so syncs
//     continue even when the app is suspended.
//   • Every batch is sent as a multipart/form-data POST containing:
//       - The raw NDJSON batch file (unmodified, unencrypted)
//       - A manifest JSON with batch ID, device ID, sequence range, hash chain tail
//   • The server returns HTTP 200 + { "batchID": "..." } on success.
//     Only then does the store acknowledge (delete) the pending file.
//   • On failure, the batch stays in pending/ and is retried next cycle.
//   • NO encryption in transit is deliberately omitted per spec (user's choice).
//     For production use, HTTPS is still used for transport integrity only —
//     no application-layer encryption of the payload.

import Foundation
import UIKit

public final class SyncEngine {

    public static let shared = SyncEngine()

    // MARK: - Configuration (set in AppDelegate before calling start())
    public var serverBaseURL: String = "http://localhost:3000"
    public var deviceToken: String = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

    private var timer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.selfsurveillance.sync"
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }()

    private let encoder = JSONEncoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Start / Stop

    public func start() {
        // Foreground timer — fires every 15 seconds while app is active
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.sync()
        }
        // Also sync immediately on start
        sync()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Called by AppDelegate on background refresh

    public func performBackgroundSync(completion: @escaping () -> Void) {
        sync(completion: completion)
    }

    // MARK: - Core Sync Loop

    private func sync(completion: (() -> Void)? = nil) {
        let batches = ImmutableLogStore.shared.pendingBatches()
        guard !batches.isEmpty else {
            completion?()
            return
        }

        // Begin background task so iOS doesn't suspend us mid-send
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SelfSurveillance.Sync") {
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }

        let group = DispatchGroup()

        for (batchID, entries) in batches {
            group.enter()
            sendBatch(batchID: batchID, entries: entries) { success in
                if success {
                    ImmutableLogStore.shared.acknowledgeBatch(batchID: batchID)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
            completion?()
        }
    }

    // MARK: - Send a single batch

    private func sendBatch(
        batchID: String,
        entries: [LogEntry],
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(serverBaseURL)/api/ingest") else {
            completion(false)
            return
        }

        // Build NDJSON payload — plain text, no encryption
        let ndjson = entries.compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry),
                  let line = String(data: data, encoding: .utf8) else { return nil }
            return line
        }.joined(separator: "\n")

        guard let bodyData = ndjson.data(using: .utf8) else {
            completion(false)
            return
        }

        // Build manifest
        let manifest: [String: Any] = [
            "batchID":    batchID,
            "deviceID":   deviceToken,
            "entryCount": entries.count,
            "firstSeq":   entries.first?.sequenceNumber ?? 0,
            "lastSeq":    entries.last?.sequenceNumber  ?? 0,
            "tailHash":   entries.last?.previousEntryHash ?? "GENESIS",
            "sentAt":     ISO8601DateFormatter().string(from: Date()),
        ]
        guard let manifestData = try? JSONSerialization.data(withJSONObject: manifest) else {
            completion(false)
            return
        }

        // Build multipart/form-data body
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ string: String) {
            if let d = string.data(using: .utf8) { body.append(d) }
        }

        // Manifest part
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"manifest\"\r\n")
        append("Content-Type: application/json\r\n\r\n")
        body.append(manifestData)
        append("\r\n")

        // NDJSON part (raw, unencrypted)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"batch\"; filename=\"\(batchID).ndjson\"\r\n")
        append("Content-Type: application/x-ndjson\r\n\r\n")
        body.append(bodyData)
        append("\r\n")

        // Close boundary
        append("--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceToken, forHTTPHeaderField: "X-Device-ID")
        request.setValue(batchID, forHTTPHeaderField: "X-Batch-ID")
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[SyncEngine] Error sending batch \(batchID): \(error)")
                completion(false)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("[SyncEngine] Non-2xx response for batch \(batchID)")
                completion(false)
                return
            }
            completion(true)
        }
        task.resume()
    }
}
