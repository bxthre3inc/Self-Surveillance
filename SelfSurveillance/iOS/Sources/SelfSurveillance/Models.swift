// MARK: - Models.swift
// Self Surveillance — Core Data Models
// All entries are append-only. Once written, nothing is ever mutated or deleted.

import Foundation

// MARK: - Log Entry (universal envelope)

/// Every piece of captured data is wrapped in this envelope before being
/// written to the local WORM store and synced to the server.
/// The `rawBytes` field carries the pre-decryption, pre-processing bytes
/// exactly as received from the OS API — no transformation applied.
public struct LogEntry: Codable, Identifiable {
    public let id: UUID                    // Immutable, generated once
    public let timestamp: Date             // Device clock at capture time
    public let deviceID: String            // UIDevice.current.identifierForVendor
    public let deviceName: String          // UIDevice.current.name
    public let iOSVersion: String          // UIDevice.current.systemVersion
    public let source: DataSource          // Which collector produced this
    public let category: DataCategory     // Coarse grouping for file tree
    public let appBundleID: String?       // Associated app, if any
    public let appDisplayName: String?    // Human-readable app name
    public let eventType: String           // Fine-grained event name
    public let payload: LogPayload         // Typed payload union
    public let rawBytes: Data?             // Raw bytes from OS, pre-decryption
    public let sequenceNumber: UInt64      // Monotonically increasing, per device
    public let previousEntryHash: String   // SHA-256 of previous entry (chain integrity)

    public init(
        timestamp: Date = Date(),
        deviceID: String,
        deviceName: String,
        iOSVersion: String,
        source: DataSource,
        category: DataCategory,
        appBundleID: String? = nil,
        appDisplayName: String? = nil,
        eventType: String,
        payload: LogPayload,
        rawBytes: Data? = nil,
        sequenceNumber: UInt64,
        previousEntryHash: String
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.iOSVersion = iOSVersion
        self.source = source
        self.category = category
        self.appBundleID = appBundleID
        self.appDisplayName = appDisplayName
        self.eventType = eventType
        self.payload = payload
        self.rawBytes = rawBytes
        self.sequenceNumber = sequenceNumber
        self.previousEntryHash = previousEntryHash
    }
}

// MARK: - Data Sources

public enum DataSource: String, Codable, CaseIterable {
    case appUsage            = "app_usage"
    case notifications       = "notifications"
    case clipboard           = "clipboard"
    case photoLibrary        = "photo_library"
    case contacts            = "contacts"
    case calendar            = "calendar"
    case safariHistory       = "safari_history"
    case health              = "health"
    case location            = "location"
    case appInstalls         = "app_installs"
    case screenTime          = "screen_time"
    case wifi                = "wifi"
    case bluetooth           = "bluetooth"
    case deviceState         = "device_state"
    case focusMode           = "focus_mode"
    case notes               = "notes"
    case files               = "files"
    case keychain            = "keychain"
    case network             = "network"
    case systemEvents        = "system_events"
    case packetFlow          = "packet_flow"
    case dnsQuery            = "dns_query"
}

// MARK: - Data Categories (for file tree grouping)

public enum DataCategory: String, Codable, CaseIterable {
    case communication       = "Communication"
    case media               = "Media"
    case browsing            = "Browsing"
    case health              = "Health & Fitness"
    case location            = "Location"
    case security            = "Security & Accounts"
    case deviceActivity      = "Device Activity"
    case files               = "Files & Storage"
    case system              = "System"
}

// MARK: - Payload Union

public enum LogPayload: Codable {
    case appUsage(AppUsagePayload)
    case notification(NotificationPayload)
    case clipboard(ClipboardPayload)
    case photoEvent(PhotoEventPayload)
    case contactChange(ContactChangePayload)
    case calendarEvent(CalendarEventPayload)
    case browsingSnapshot(BrowsingSnapshotPayload)
    case healthSample(HealthSamplePayload)
    case locationVisit(LocationVisitPayload)
    case appInstall(AppInstallPayload)
    case wifiEvent(WiFiEventPayload)
    case bluetoothEvent(BluetoothEventPayload)
    case deviceState(DeviceStatePayload)
    case focusMode(FocusModePayload)
    case noteChange(NoteChangePayload)
    case fileChange(FileChangePayload)
    case keychainEvent(KeychainEventPayload)
    case networkRequest(NetworkRequestPayload)
    case systemEvent(SystemEventPayload)
    case packetFlow(PacketFlowPayload)
    case dnsQuery(DNSQueryPayload)
    case raw([String: String])             // Fallback for untyped events

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .appUsage(let p):          try container.encode("appUsage", forKey: .type); try container.encode(p, forKey: .data)
        case .notification(let p):      try container.encode("notification", forKey: .type); try container.encode(p, forKey: .data)
        case .clipboard(let p):         try container.encode("clipboard", forKey: .type); try container.encode(p, forKey: .data)
        case .photoEvent(let p):        try container.encode("photoEvent", forKey: .type); try container.encode(p, forKey: .data)
        case .contactChange(let p):     try container.encode("contactChange", forKey: .type); try container.encode(p, forKey: .data)
        case .calendarEvent(let p):     try container.encode("calendarEvent", forKey: .type); try container.encode(p, forKey: .data)
        case .browsingSnapshot(let p):  try container.encode("browsingSnapshot", forKey: .type); try container.encode(p, forKey: .data)
        case .healthSample(let p):      try container.encode("healthSample", forKey: .type); try container.encode(p, forKey: .data)
        case .locationVisit(let p):     try container.encode("locationVisit", forKey: .type); try container.encode(p, forKey: .data)
        case .appInstall(let p):        try container.encode("appInstall", forKey: .type); try container.encode(p, forKey: .data)
        case .wifiEvent(let p):         try container.encode("wifiEvent", forKey: .type); try container.encode(p, forKey: .data)
        case .bluetoothEvent(let p):    try container.encode("bluetoothEvent", forKey: .type); try container.encode(p, forKey: .data)
        case .deviceState(let p):       try container.encode("deviceState", forKey: .type); try container.encode(p, forKey: .data)
        case .focusMode(let p):         try container.encode("focusMode", forKey: .type); try container.encode(p, forKey: .data)
        case .noteChange(let p):        try container.encode("noteChange", forKey: .type); try container.encode(p, forKey: .data)
        case .fileChange(let p):        try container.encode("fileChange", forKey: .type); try container.encode(p, forKey: .data)
        case .keychainEvent(let p):     try container.encode("keychainEvent", forKey: .type); try container.encode(p, forKey: .data)
        case .networkRequest(let p):    try container.encode("networkRequest", forKey: .type); try container.encode(p, forKey: .data)
        case .systemEvent(let p):       try container.encode("systemEvent", forKey: .type); try container.encode(p, forKey: .data)
        case .packetFlow(let p):        try container.encode("packetFlow", forKey: .type); try container.encode(p, forKey: .data)
        case .dnsQuery(let p):          try container.encode("dnsQuery", forKey: .type); try container.encode(p, forKey: .data)
        case .raw(let p):               try container.encode("raw", forKey: .type); try container.encode(p, forKey: .data)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "appUsage":         self = .appUsage(try container.decode(AppUsagePayload.self, forKey: .data))
        case "notification":     self = .notification(try container.decode(NotificationPayload.self, forKey: .data))
        case "clipboard":        self = .clipboard(try container.decode(ClipboardPayload.self, forKey: .data))
        case "photoEvent":       self = .photoEvent(try container.decode(PhotoEventPayload.self, forKey: .data))
        case "contactChange":    self = .contactChange(try container.decode(ContactChangePayload.self, forKey: .data))
        case "calendarEvent":    self = .calendarEvent(try container.decode(CalendarEventPayload.self, forKey: .data))
        case "browsingSnapshot": self = .browsingSnapshot(try container.decode(BrowsingSnapshotPayload.self, forKey: .data))
        case "healthSample":     self = .healthSample(try container.decode(HealthSamplePayload.self, forKey: .data))
        case "locationVisit":    self = .locationVisit(try container.decode(LocationVisitPayload.self, forKey: .data))
        case "appInstall":       self = .appInstall(try container.decode(AppInstallPayload.self, forKey: .data))
        case "wifiEvent":        self = .wifiEvent(try container.decode(WiFiEventPayload.self, forKey: .data))
        case "bluetoothEvent":   self = .bluetoothEvent(try container.decode(BluetoothEventPayload.self, forKey: .data))
        case "deviceState":      self = .deviceState(try container.decode(DeviceStatePayload.self, forKey: .data))
        case "focusMode":        self = .focusMode(try container.decode(FocusModePayload.self, forKey: .data))
        case "noteChange":       self = .noteChange(try container.decode(NoteChangePayload.self, forKey: .data))
        case "fileChange":       self = .fileChange(try container.decode(FileChangePayload.self, forKey: .data))
        case "keychainEvent":    self = .keychainEvent(try container.decode(KeychainEventPayload.self, forKey: .data))
        case "networkRequest":   self = .networkRequest(try container.decode(NetworkRequestPayload.self, forKey: .data))
        case "systemEvent":      self = .systemEvent(try container.decode(SystemEventPayload.self, forKey: .data))
        case "packetFlow":       self = .packetFlow(try container.decode(PacketFlowPayload.self, forKey: .data))
        case "dnsQuery":         self = .dnsQuery(try container.decode(DNSQueryPayload.self, forKey: .data))
        default:                 self = .raw(try container.decode([String: String].self, forKey: .data))
        }
    }
}

// MARK: - Individual Payload Types

public struct AppUsagePayload: Codable {
    public let bundleID: String
    public let displayName: String
    public let event: String              // "foregrounded" | "backgrounded" | "launched" | "terminated"
    public let durationSeconds: Double?   // For backgrounded events
    public let screenCategory: String?    // Screen Time category (e.g. "Social Networking")
}

public struct NotificationPayload: Codable {
    public let bundleID: String
    public let appName: String
    public let title: String?
    public let subtitle: String?
    public let body: String?
    public let categoryIdentifier: String?
    public let threadIdentifier: String?
    public let actionTaken: String        // "delivered" | "dismissed" | "tapped" | "actioned" | "cleared"
    public let dismissalLatencySeconds: Double?
    public let badgeCount: Int?
    public let isRemote: Bool
    public let rawAPNSPayload: String?    // Raw APNS dict as JSON string, pre-decryption
}

public struct ClipboardPayload: Codable {
    public let contentType: String        // "text" | "url" | "image" | "file" | "other"
    public let textContent: String?       // If text/URL
    public let imageDataBase64: String?   // If image (thumbnail only, max 256px)
    public let fileName: String?          // If file
    public let sourceApp: String?         // App that wrote to clipboard
    public let byteSize: Int
}

public struct PhotoEventPayload: Codable {
    public let eventKind: String          // "added" | "deleted" | "modified" | "albumCreated" | "albumDeleted"
    public let assetLocalID: String
    public let fileName: String?
    public let mediaType: String          // "image" | "video" | "livePhoto"
    public let creationDate: Date?
    public let location: String?          // "lat,lon" string if available
    public let isFavorite: Bool?
    public let isHidden: Bool?
    public let albumName: String?
    public let thumbnailBase64: String?   // 128x128 JPEG thumbnail
    public let exifMetadata: [String: String]?
}

public struct ContactChangePayload: Codable {
    public let changeType: String         // "added" | "deleted" | "modified"
    public let contactID: String
    public let displayName: String?
    public let phoneNumbers: [String]?
    public let emailAddresses: [String]?
    public let note: String?
    public let organizationName: String?
    public let modifiedFields: [String]?  // Which fields changed
}

public struct CalendarEventPayload: Codable {
    public let changeType: String         // "added" | "deleted" | "modified"
    public let eventID: String
    public let title: String?
    public let notes: String?
    public let startDate: Date?
    public let endDate: Date?
    public let calendarName: String?
    public let calendarType: String?      // "local" | "caldav" | "exchange" | "icloud"
    public let attendees: [String]?
    public let location: String?
    public let url: String?
    public let isAllDay: Bool?
    public let recurrenceRule: String?
}

public struct BrowsingSnapshotPayload: Codable {
    public let browser: String            // "Safari" | "Chrome" | "Firefox" | etc.
    public let url: String
    public let pageTitle: String?
    public let visitDate: Date
    public let durationSeconds: Double?
    public let referrerURL: String?
    public let isPrivateMode: Bool?
    public let searchTerms: String?       // If visit was from a search
    public let formInputSnapshot: String? // Spotlight-abandoned-input style capture
}

public struct HealthSamplePayload: Codable {
    public let quantityType: String       // "stepCount" | "heartRate" | "sleepAnalysis" | etc.
    public let value: Double?
    public let unit: String?
    public let startDate: Date
    public let endDate: Date
    public let sourceApp: String?
    public let device: String?
    public let metadata: [String: String]?
}

public struct LocationVisitPayload: Codable {
    public let eventType: String          // "visit" | "significantChange" | "regionEntry" | "regionExit"
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    public let horizontalAccuracy: Double?
    public let arrivalDate: Date?
    public let departureDate: Date?
    public let placemark: String?         // Reverse-geocoded address
    public let speed: Double?
    public let course: Double?
    public let floor: Int?
}

public struct AppInstallPayload: Codable {
    public let eventType: String          // "installed" | "uninstalled" | "updated"
    public let bundleID: String
    public let displayName: String
    public let version: String?
    public let previousVersion: String?
    public let sizeBytes: Int64?
    public let category: String?
    public let developerName: String?
}

public struct WiFiEventPayload: Codable {
    public let eventType: String          // "connected" | "disconnected" | "probeRequest" | "seen"
    public let ssid: String?
    public let bssid: String?
    public let rssi: Int?
    public let securityType: String?      // "WPA2" | "WPA3" | "Open" | etc.
    public let frequency: Double?         // 2.4 or 5 GHz
    public let ipAddress: String?
}

public struct BluetoothEventPayload: Codable {
    public let eventType: String          // "connected" | "disconnected" | "discovered" | "paired" | "unpaired"
    public let deviceName: String?
    public let deviceAddress: String?
    public let deviceClass: String?       // "headphones" | "keyboard" | "watch" | etc.
    public let rssi: Int?
    public let serviceUUIDs: [String]?
    public let pairingLatencySeconds: Double?
}

public struct DeviceStatePayload: Codable {
    public let batteryLevel: Float?       // 0.0 to 1.0
    public let batteryState: String?      // "charging" | "full" | "unplugged"
    public let isLowPowerMode: Bool?
    public let brightness: Float?         // 0.0 to 1.0
    public let volume: Float?
    public let orientation: String?       // "portrait" | "landscape" | "faceUp" | "faceDown"
    public let unlockMethod: String?      // "faceID" | "passcode" | "appleWatch" | "failed"
    public let isLocked: Bool?
    public let airplaneMode: Bool?
    public let cellularDataEnabled: Bool?
    public let wifiEnabled: Bool?
    public let bluetoothEnabled: Bool?
    public let locationServicesEnabled: Bool?
    public let uptimeSeconds: Double?
    public let thermalState: String?      // "nominal" | "fair" | "serious" | "critical"
    public let availableStorageGB: Double?
    public let totalStorageGB: Double?
    public let connectedChargerID: String? // MagSafe/charger handshake serial
    public let connectedDisplayID: String? // External display serial
    public let carPlayVehicleID: String?   // CarPlay VIN if connected
}

public struct FocusModePayload: Codable {
    public let eventType: String          // "activated" | "deactivated" | "automationTriggered"
    public let modeName: String           // "Do Not Disturb" | "Work" | "Sleep" | "Personal" | custom
    public let trigger: String?           // "manual" | "schedule" | "location" | "app"
    public let allowedApps: [String]?
    public let allowedContacts: [String]?
}

public struct NoteChangePayload: Codable {
    public let changeType: String         // "created" | "modified" | "deleted" | "moved"
    public let noteID: String
    public let title: String?
    public let bodySnippet: String?       // First 500 chars of note body
    public let folderName: String?
    public let accountName: String?       // "iCloud" | "On My iPhone" | etc.
    public let hasAttachments: Bool?
    public let attachmentTypes: [String]?
    public let wordCount: Int?
    public let lockedByPassword: Bool?
}

public struct FileChangePayload: Codable {
    public let changeType: String         // "created" | "modified" | "deleted" | "moved" | "renamed"
    public let filePath: String
    public let fileName: String
    public let fileExtension: String?
    public let fileSizeBytes: Int64?
    public let sourceApp: String?
    public let storageLocation: String?   // "iCloudDrive" | "OnMyiPhone" | "ThirdParty"
    public let previousPath: String?      // For move/rename events
    public let contentSnippet: String?    // First 256 chars if plaintext
}

public struct KeychainEventPayload: Codable {
    public let eventType: String          // "created" | "accessed" | "modified" | "deleted" | "autofilled"
    public let service: String?           // The keychain service label
    public let account: String?           // The account name (not the password)
    public let accessGroup: String?
    public let isPasskey: Bool?
    public let twoFACodeAutofilled: Bool?
    public let biometricRequired: Bool?
}

public struct NetworkRequestPayload: Codable {
    public let eventType: String          // "request" | "response" | "failure" | "blocked"
    public let sourceApp: String?
    public let url: String?
    public let domain: String?
    public let httpMethod: String?
    public let statusCode: Int?
    public let bytesSent: Int64?
    public let bytesReceived: Int64?
    public let isEncrypted: Bool?         // HTTPS vs HTTP
    public let certificateInfo: String?
}

public struct SystemEventPayload: Codable {
    public let eventType: String          // "reboot" | "crash" | "update" | "backup" | "restore" | "mdmProfileInstalled" | "developerModeToggled" | "analyticsOptOut"
    public let description: String?
    public let version: String?
    public let metadata: [String: String]?
}

public struct PacketFlowPayload: Codable {
    public let event: String             // "open" | "outbound" | "inbound" | "close"
    public let proto: String?            // "TCP" | "UDP"
    public let direction: String?        // "out" | "in"
    public let sourceIP: String?
    public let sourcePort: Int?
    public let destIP: String?
    public let destPort: Int?
    public let byteCount: Int64?         // Bytes in this chunk (0 for open/close)
    public let totalBytesSent: Int64?    // Cumulative for this flow (close event only)
    public let totalBytesReceived: Int64? // Cumulative for this flow (close event only)
    public let appBundleID: String?
    public let payloadSnippetBase64: String? // First 256 bytes of payload, base64
}

public struct DNSQueryPayload: Codable {
    public let hostname: String
    public let queryType: String         // "A" | "AAAA" | "PTR" | "CNAME"
    public let resolvedAddresses: [String]?
    public let responseTimeMs: Double?
    public let ttl: Int?
    public let sourceApp: String?
    public let error: String?
}
