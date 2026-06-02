// MARK: - BackgroundTaskManager.swift
// Registers and handles all iOS background execution modes to keep the
// surveillance running as continuously as possible.
//
// Strategies used (layered, most persistent first):
//   1. BGProcessingTask — long background processing (device charging + idle)
//   2. BGAppRefreshTask — periodic ~15 min background refresh
//   3. Silent push notifications — server can trigger a background wake
//   4. Location significant change — wakes app on cell tower change
//   5. VoIP (PushKit PKPushRegistry) — guaranteed instant wake on push
//   6. URLSession background transfer — data upload can complete after suspend
//
// The app's Info.plist must declare:
//   UIBackgroundModes: fetch, processing, location, remote-notification, voip

import BackgroundTasks
import UIKit
import PushKit

public final class BackgroundTaskManager: NSObject, PKPushRegistryDelegate {

    public static let shared = BackgroundTaskManager()

    private static let processingTaskID   = "com.selfsurveillance.processing"
    private static let appRefreshTaskID   = "com.selfsurveillance.refresh"

    private var voipRegistry: PKPushRegistry?

    private override init() { super.init() }

    // MARK: - Register (call from AppDelegate.application(_:didFinishLaunchingWithOptions:))

    public func registerTasks() {
        // BGProcessingTask
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskManager.processingTaskID,
            using: nil
        ) { task in
            self.handleProcessingTask(task as! BGProcessingTask)
        }

        // BGAppRefreshTask
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskManager.appRefreshTaskID,
            using: nil
        ) { task in
            self.handleAppRefreshTask(task as! BGAppRefreshTask)
        }
    }

    // MARK: - Schedule (call from AppDelegate.applicationDidEnterBackground)

    public func scheduleBackgroundTasks() {
        scheduleProcessingTask()
        scheduleAppRefreshTask()
    }

    private func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskManager.processingTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15)   // As soon as possible
        try? BGTaskScheduler.shared.submit(request)
    }

    private func scheduleAppRefreshTask() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskManager.appRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Task Handlers

    private func handleProcessingTask(_ task: BGProcessingTask) {
        scheduleProcessingTask()   // Reschedule immediately

        let group = DispatchGroup()

        // Run all collectors
        group.enter()
        CollectorOrchestrator.shared.runAllCollectors {
            group.leave()
        }

        // Sync pending batches
        group.enter()
        SyncEngine.shared.performBackgroundSync {
            group.leave()
        }

        group.notify(queue: .main) {
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            // Even if expired, mark complete — iOS will retry via scheduleProcessingTask
            task.setTaskCompleted(success: false)
        }
    }

    private func handleAppRefreshTask(_ task: BGAppRefreshTask) {
        scheduleAppRefreshTask()   // Reschedule immediately

        SyncEngine.shared.performBackgroundSync {
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - PushKit VoIP (most reliable background wake mechanism on iOS)

    public func startVoIPPush() {
        voipRegistry = PKPushRegistry(queue: .main)
        voipRegistry?.delegate = self
        voipRegistry?.desiredPushTypes = [.voIP]
    }

    public func pushRegistry(_ registry: PKPushRegistry,
                              didUpdate pushCredentials: PKPushCredentials,
                              for type: PKPushType) {
        // Send the VoIP push token to the backend so it can wake us when needed
        let tokenString = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        SyncEngine.shared.registerVoIPToken(tokenString)
    }

    public func pushRegistry(_ registry: PKPushRegistry,
                              didReceiveIncomingPushWith payload: PKPushPayload,
                              for type: PKPushType,
                              completion: @escaping () -> Void) {
        // A push was received — run sync immediately
        SyncEngine.shared.performBackgroundSync {
            completion()
        }
    }
}
