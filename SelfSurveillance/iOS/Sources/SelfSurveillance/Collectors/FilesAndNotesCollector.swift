// MARK: - FilesAndNotesCollector.swift
// Monitors iCloud Drive and local "On My iPhone" file changes via
// NSMetadataQuery (which observes NSMetadataQueryDidUpdateNotification),
// and monitors Notes via the Notes app's shared Core Data store
// (where readable via file system observation).

import Foundation

public final class FilesAndNotesCollector {

    public static let shared = FilesAndNotesCollector()

    // iCloud Drive metadata query
    private var iCloudQuery: NSMetadataQuery?
    // Local Documents metadata query
    private var localQuery: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var lastKnownFiles: [String: Int64] = [:]   // path → size (for change detection)

    private init() {}

    public func start() {
        setupiCloudQuery()
        setupLocalQuery()
        watchNotesDatabase()
    }

    public func stop() {
        iCloudQuery?.stop()
        localQuery?.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: - iCloud Drive

    private func setupiCloudQuery() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope,
                              NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(value: true)
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]

        iCloudQuery = query

        let obs = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] notification in
            self?.handleMetadataUpdate(notification, storage: "iCloudDrive")
        }
        observers.append(obs)

        OperationQueue.main.addOperation { query.start() }
    }

    // MARK: - Local Files

    private func setupLocalQuery() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryLocalDocumentsScope]
        query.predicate = NSPredicate(value: true)

        localQuery = query

        let obs = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] notification in
            self?.handleMetadataUpdate(notification, storage: "OnMyiPhone")
        }
        observers.append(obs)

        OperationQueue.main.addOperation { query.start() }
    }

    private func handleMetadataUpdate(_ notification: Notification, storage: String) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        let added   = (notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]) ?? []
        let removed = (notification.userInfo?[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem]) ?? []
        let changed = (notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem]) ?? []

        for item in added   { logFileItem(item, changeType: "created",  storage: storage) }
        for item in removed { logFileItem(item, changeType: "deleted",  storage: storage) }
        for item in changed { logFileItem(item, changeType: "modified", storage: storage) }
    }

    private func logFileItem(_ item: NSMetadataItem, changeType: String, storage: String) {
        let path  = item.value(forAttribute: NSMetadataItemPathKey) as? String ?? ""
        let name  = item.value(forAttribute: NSMetadataItemFSNameKey) as? String ?? ""
        let ext   = (name as NSString).pathExtension
        let size  = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64

        var snippet: String? = nil
        // For text files, grab first 256 bytes as content snippet
        let textExtensions = ["txt", "md", "rtf", "csv", "json", "xml", "html", "log"]
        if textExtensions.contains(ext.lowercased()),
           let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
           let handle  = try? FileHandle(forReadingFrom: fileURL) {
            let data = handle.readData(ofLength: 256)
            snippet  = String(data: data, encoding: .utf8)
            try? handle.close()
        }

        ImmutableLogStore.shared.append(
            source: .files,
            category: .files,
            eventType: changeType,
            payload: .fileChange(FileChangePayload(
                changeType: changeType,
                filePath: path,
                fileName: name,
                fileExtension: ext.isEmpty ? nil : ext,
                fileSizeBytes: size,
                sourceApp: nil,
                storageLocation: storage,
                previousPath: nil,
                contentSnippet: snippet
            ))
        )
    }

    // MARK: - Notes Database Watcher

    private func watchNotesDatabase() {
        // The Notes app stores data in:
        // ~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite
        // We cannot read the database directly, but we CAN observe the file's
        // modification date to detect when notes change, then log the event.
        // For the actual content, we use the Notes share extension when available.

        let notesContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.apple.notes"
        )

        guard let storeURL = notesContainer?.appendingPathComponent("NoteStore.sqlite") else { return }

        var lastModDate: Date? = nil

        // Poll every 15 seconds alongside the sync cycle
        let timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: storeURL.path),
                  let modDate = attrs[.modificationDate] as? Date else { return }
            if lastModDate == nil || modDate > lastModDate! {
                lastModDate = modDate
                self?.logNotesChanged()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func logNotesChanged() {
        ImmutableLogStore.shared.append(
            source: .notes,
            category: .files,
            eventType: "notesStoreModified",
            payload: .noteChange(NoteChangePayload(
                changeType: "modified",
                noteID: "store",
                title: nil,
                bodySnippet: nil,
                folderName: nil,
                accountName: nil,
                hasAttachments: nil,
                attachmentTypes: nil,
                wordCount: nil,
                lockedByPassword: nil
            ))
        )
    }
}
