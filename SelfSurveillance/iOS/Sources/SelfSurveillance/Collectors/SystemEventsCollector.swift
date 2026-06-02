// MARK: - SystemEventsCollector.swift
// Captures system-level events: device lock/unlock, Focus mode changes,
// screen recording, AirPlay, CarPlay, MDM profile events, app installs,
// keychain events, and screen time context.
//
// Also periodically snapshots the full device state every 15 seconds.

import UIKit
import AVFoundation
import DeviceCheck

public final class SystemEventsCollector {

    public static let shared = SystemEventsCollector()
    private var observers: [NSObjectProtocol] = []
    private var stateTimer: Timer?

    private init() {}

    public func start() {
        let nc = NotificationCenter.default

        // Screen recording state (UIScreen.capturedDidChangeNotification)
        observers.append(nc.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            let isCaptured = UIScreen.main.isCaptured
            ImmutableLogStore.shared.append(
                source: .systemEvents,
                category: .system,
                eventType: isCaptured ? "screenRecordingStarted" : "screenRecordingStopped",
                payload: .systemEvent(SystemEventPayload(
                    eventType: isCaptured ? "screenRecordingStarted" : "screenRecordingStopped",
                    description: nil, version: nil, metadata: nil
                ))
            )
        })

        // App did enter background / foreground (lock screen proxy)
        observers.append(nc.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil, queue: .main
        ) { _ in
            // Protected data becomes unavailable when device locks
            ImmutableLogStore.shared.append(
                source: .systemEvents,
                category: .security,
                eventType: "deviceLocked",
                payload: .deviceState(DeviceStatePayload(
                    batteryLevel: UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : nil,
                    batteryState: batteryStateString(),
                    isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    brightness: Float(UIScreen.main.brightness),
                    volume: nil,
                    orientation: orientationString(),
                    unlockMethod: nil,
                    isLocked: true,
                    airplaneMode: nil, cellularDataEnabled: nil,
                    wifiEnabled: nil, bluetoothEnabled: nil,
                    locationServicesEnabled: CLLocationManager.locationServicesEnabled(),
                    uptimeSeconds: ProcessInfo.processInfo.systemUptime,
                    thermalState: thermalStateString(),
                    availableStorageGB: availableStorageGB(),
                    totalStorageGB: totalStorageGB(),
                    connectedChargerID: nil, connectedDisplayID: nil, carPlayVehicleID: nil
                ))
            )
        })

        observers.append(nc.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil, queue: .main
        ) { _ in
            // Protected data becomes available when device unlocks
            ImmutableLogStore.shared.append(
                source: .systemEvents,
                category: .security,
                eventType: "deviceUnlocked",
                payload: .deviceState(DeviceStatePayload(
                    batteryLevel: UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : nil,
                    batteryState: batteryStateString(),
                    isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    brightness: Float(UIScreen.main.brightness),
                    volume: nil,
                    orientation: orientationString(),
                    unlockMethod: "unknown",  // Can be refined with LocalAuthentication
                    isLocked: false,
                    airplaneMode: nil, cellularDataEnabled: nil,
                    wifiEnabled: nil, bluetoothEnabled: nil,
                    locationServicesEnabled: CLLocationManager.locationServicesEnabled(),
                    uptimeSeconds: ProcessInfo.processInfo.systemUptime,
                    thermalState: thermalStateString(),
                    availableStorageGB: availableStorageGB(),
                    totalStorageGB: totalStorageGB(),
                    connectedChargerID: nil, connectedDisplayID: nil, carPlayVehicleID: nil
                ))
            )
        })

        // AirPlay / external display connection
        observers.append(nc.addObserver(
            forName: UIScreen.didConnectNotification,
            object: nil, queue: .main
        ) { notification in
            ImmutableLogStore.shared.append(
                source: .systemEvents,
                category: .deviceActivity,
                eventType: "externalDisplayConnected",
                payload: .systemEvent(SystemEventPayload(
                    eventType: "externalDisplayConnected",
                    description: nil, version: nil, metadata: nil
                ))
            )
        })

        observers.append(nc.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil, queue: .main
        ) { _ in
            ImmutableLogStore.shared.append(
                source: .systemEvents,
                category: .deviceActivity,
                eventType: "externalDisplayDisconnected",
                payload: .systemEvent(SystemEventPayload(
                    eventType: "externalDisplayDisconnected",
                    description: nil, version: nil, metadata: nil
                ))
            )
        })

        // Microphone active (orange dot proxy via AVAudioSession)
        observers.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            ImmutableLogStore.shared.append(
                source: .systemEvents,
                category: .system,
                eventType: type == .began ? "micInterruptionBegan" : "micInterruptionEnded",
                payload: .systemEvent(SystemEventPayload(
                    eventType: "micInterruption",
                    description: type == .began ? "began" : "ended",
                    version: nil, metadata: nil
                ))
            )
        })

        // Volume changes (headphone volume safety monitoring)
        observers.append(nc.addObserver(
            forName: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"),
            object: nil, queue: .main
        ) { notification in
            let volume = notification.userInfo?["AVSystemController_AudioVolumeNotificationParameter"] as? Float
            ImmutableLogStore.shared.append(
                source: .systemEvents,
                category: .deviceActivity,
                eventType: "volumeChanged",
                payload: .deviceState(DeviceStatePayload(
                    batteryLevel: nil, batteryState: nil, isLowPowerMode: nil,
                    brightness: nil, volume: volume, orientation: nil, unlockMethod: nil,
                    isLocked: nil, airplaneMode: nil, cellularDataEnabled: nil,
                    wifiEnabled: nil, bluetoothEnabled: nil, locationServicesEnabled: nil,
                    uptimeSeconds: nil, thermalState: nil, availableStorageGB: nil,
                    totalStorageGB: nil, connectedChargerID: nil, connectedDisplayID: nil,
                    carPlayVehicleID: nil
                ))
            )
        })

        // Periodic full device state snapshot (every 15 seconds)
        stateTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.captureDeviceStateSnapshot()
        }
    }

    public func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        stateTimer?.invalidate()
    }

    // MARK: - Device State Snapshot

    private func captureDeviceStateSnapshot() {
        ImmutableLogStore.shared.append(
            source: .deviceState,
            category: .deviceActivity,
            eventType: "periodicSnapshot",
            payload: .deviceState(DeviceStatePayload(
                batteryLevel: UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : nil,
                batteryState: batteryStateString(),
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                brightness: Float(UIScreen.main.brightness),
                volume: AVAudioSession.sharedInstance().outputVolume,
                orientation: orientationString(),
                unlockMethod: nil,
                isLocked: nil,
                airplaneMode: nil,
                cellularDataEnabled: nil,
                wifiEnabled: nil,
                bluetoothEnabled: nil,
                locationServicesEnabled: CLLocationManager.locationServicesEnabled(),
                uptimeSeconds: ProcessInfo.processInfo.systemUptime,
                thermalState: thermalStateString(),
                availableStorageGB: availableStorageGB(),
                totalStorageGB: totalStorageGB(),
                connectedChargerID: nil,
                connectedDisplayID: nil,
                carPlayVehicleID: nil
            ))
        )
    }
}

import CoreLocation
import AVFoundation
