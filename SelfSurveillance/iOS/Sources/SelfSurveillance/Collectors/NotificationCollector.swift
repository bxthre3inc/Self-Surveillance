// MARK: - NotificationCollector.swift
// Captures every incoming notification at the UNUserNotificationCenter layer —
// BEFORE any app-level processing or decryption occurs.
// We implement UNUserNotificationCenterDelegate to intercept willPresent and
// didReceive callbacks, plus we observe NSNotificationCenter for system events.
//
// Raw APNS payload is captured as a JSON string from the userInfo dictionary,
// which is the original push payload delivered by APNs before any transformation.

import UIKit
import UserNotifications

public final class NotificationCollector: NSObject, UNUserNotificationCenterDelegate {

    public static let shared = NotificationCollector()
    private var deliveredAt: [String: Date] = [:]  // notificationID → delivery time

    private override init() { super.init() }

    public func start() {
        // Become the notification center delegate (app must not override this)
        UNUserNotificationCenter.current().delegate = self

        // Request authorization if needed
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound, .provisional]
        ) { granted, error in
            ImmutableLogStore.shared.append(
                source: .notifications,
                category: .system,
                eventType: "notificationAuthorizationStatus",
                payload: .systemEvent(SystemEventPayload(
                    eventType: "notificationAuthorizationStatus",
                    description: "granted=\(granted) error=\(error?.localizedDescription ?? "none")",
                    version: nil,
                    metadata: nil
                ))
            )
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification is about to be presented while app is in foreground.
    /// This is the earliest possible interception point — before the system renders the banner.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        captureNotification(notification, action: "delivered")
        completionHandler([.banner, .badge, .sound, .list])
    }

    /// Called when the user interacts with a notification (tap, action, dismiss).
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let notification = response.notification
        var action = "unknown"
        var latency: Double? = nil

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            action = "tapped"
        case UNNotificationDismissActionIdentifier:
            action = "dismissed"
        default:
            action = "actioned:\(response.actionIdentifier)"
        }

        if let deliveredTime = deliveredAt[notification.request.identifier] {
            latency = Date().timeIntervalSince(deliveredTime)
            deliveredAt.removeValue(forKey: notification.request.identifier)
        }

        captureNotification(notification, action: action, dismissalLatency: latency)
        completionHandler()
    }

    // MARK: - Private

    private func captureNotification(
        _ notification: UNNotification,
        action: String,
        dismissalLatency: Double? = nil
    ) {
        let request = notification.request
        let content = request.content
        deliveredAt[request.identifier] = Date()

        // Extract raw APNS userInfo as JSON string — this is the pre-decryption payload
        let rawPayload: String?
        if let jsonData = try? JSONSerialization.data(
            withJSONObject: content.userInfo, options: .sortedKeys
        ) {
            rawPayload = String(data: jsonData, encoding: .utf8)
        } else {
            rawPayload = nil
        }

        // Raw bytes of the full notification request
        let rawBytes = rawPayload?.data(using: .utf8)

        let isRemote: Bool
        switch request.trigger {
        case is UNPushNotificationTrigger: isRemote = true
        default: isRemote = false
        }

        let bundleID = content.userInfo["aps"] != nil
            ? (content.userInfo["bundle_id"] as? String ?? "unknown.remote")
            : Bundle.main.bundleIdentifier ?? "unknown.local"

        ImmutableLogStore.shared.append(
            source: .notifications,
            category: .communication,
            appBundleID: bundleID,
            eventType: action,
            payload: .notification(NotificationPayload(
                bundleID: bundleID,
                appName: content.threadIdentifier.isEmpty ? bundleID : content.threadIdentifier,
                title: content.title.isEmpty ? nil : content.title,
                subtitle: content.subtitle.isEmpty ? nil : content.subtitle,
                body: content.body.isEmpty ? nil : content.body,
                categoryIdentifier: content.categoryIdentifier.isEmpty ? nil : content.categoryIdentifier,
                threadIdentifier: content.threadIdentifier.isEmpty ? nil : content.threadIdentifier,
                actionTaken: action,
                dismissalLatencySeconds: dismissalLatency,
                badgeCount: content.badge?.intValue,
                isRemote: isRemote,
                rawAPNSPayload: rawPayload
            )),
            rawBytes: rawBytes
        )
    }
}
