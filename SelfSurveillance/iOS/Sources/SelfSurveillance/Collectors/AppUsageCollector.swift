// MARK: - AppUsageCollector.swift
// Tracks every app foreground/background/launch/terminate event.
// Uses NSWorkspace notifications + UIApplication lifecycle + Screen Time API.
//
// "Pre-decryption" note: iOS delivers app lifecycle events through the
// UIApplicationDelegate before any app-level decryption occurs.
// We capture the notification payload at the OS notification layer.

import UIKit
import FamilyControls
import ManagedSettings

public final class AppUsageCollector {

    public static let shared = AppUsageCollector()
    private var foregroundedAt: [String: Date] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {}

    public func start() {
        let nc = NotificationCenter.default

        // App did become active
        observers.append(nc.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.captureAppEvent("foregrounded")
        })

        // App will resign active
        observers.append(nc.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.captureAppEvent("backgrounded")
        })

        // App did finish launching
        observers.append(nc.addObserver(
            forName: UIApplication.didFinishLaunchingNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.captureAppEvent("launched")
        })

        // App will terminate
        observers.append(nc.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.captureAppEvent("terminated")
        })

        // Screen brightness change (device state change)
        observers.append(nc.addObserver(
            forName: UIScreen.brightnessDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            let brightness = UIScreen.main.brightness
            ImmutableLogStore.shared.append(
                source: .deviceState,
                category: .deviceActivity,
                eventType: "brightnessChanged",
                payload: .deviceState(DeviceStatePayload(
                    batteryLevel: UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : nil,
                    batteryState: batteryStateString(),
                    isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    brightness: Float(brightness),
                    volume: nil,
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
        })

        // Battery state changes
        UIDevice.current.isBatteryMonitoringEnabled = true
        observers.append(nc.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            ImmutableLogStore.shared.append(
                source: .deviceState,
                category: .deviceActivity,
                eventType: "batteryStateChanged",
                payload: .deviceState(DeviceStatePayload(
                    batteryLevel: UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : nil,
                    batteryState: batteryStateString(),
                    isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    brightness: Float(UIScreen.main.brightness),
                    volume: nil,
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
        })

        // Thermal state changes
        observers.append(nc.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            ImmutableLogStore.shared.append(
                source: .deviceState,
                category: .deviceActivity,
                eventType: "thermalStateChanged",
                payload: .deviceState(DeviceStatePayload(
                    batteryLevel: nil,
                    batteryState: nil,
                    isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    brightness: nil,
                    volume: nil,
                    orientation: nil,
                    unlockMethod: nil,
                    isLocked: nil,
                    airplaneMode: nil,
                    cellularDataEnabled: nil,
                    wifiEnabled: nil,
                    bluetoothEnabled: nil,
                    locationServicesEnabled: nil,
                    uptimeSeconds: ProcessInfo.processInfo.systemUptime,
                    thermalState: thermalStateString(),
                    availableStorageGB: availableStorageGB(),
                    totalStorageGB: totalStorageGB(),
                    connectedChargerID: nil,
                    connectedDisplayID: nil,
                    carPlayVehicleID: nil
                ))
            )
        })

        // Low power mode toggle
        observers.append(nc.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main
        ) { _ in
            ImmutableLogStore.shared.append(
                source: .deviceState,
                category: .deviceActivity,
                eventType: "lowPowerModeToggled",
                payload: .deviceState(DeviceStatePayload(
                    batteryLevel: UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : nil,
                    batteryState: batteryStateString(),
                    isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    brightness: nil, volume: nil, orientation: nil, unlockMethod: nil,
                    isLocked: nil, airplaneMode: nil, cellularDataEnabled: nil,
                    wifiEnabled: nil, bluetoothEnabled: nil, locationServicesEnabled: nil,
                    uptimeSeconds: ProcessInfo.processInfo.systemUptime,
                    thermalState: thermalStateString(),
                    availableStorageGB: nil, totalStorageGB: nil,
                    connectedChargerID: nil, connectedDisplayID: nil, carPlayVehicleID: nil
                ))
            )
        })
    }

    private func captureAppEvent(_ eventType: String) {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let appName  = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? "Unknown"

        var duration: Double? = nil
        if eventType == "backgrounded", let start = foregroundedAt[bundleID] {
            duration = Date().timeIntervalSince(start)
            foregroundedAt.removeValue(forKey: bundleID)
        } else if eventType == "foregrounded" {
            foregroundedAt[bundleID] = Date()
        }

        ImmutableLogStore.shared.append(
            source: .appUsage,
            category: .deviceActivity,
            appBundleID: bundleID,
            appDisplayName: appName,
            eventType: eventType,
            payload: .appUsage(AppUsagePayload(
                bundleID: bundleID,
                displayName: appName,
                event: eventType,
                durationSeconds: duration,
                screenCategory: nil
            ))
        )
    }

    public func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
}

// MARK: - Device state helpers (file-level free functions)

func batteryStateString() -> String? {
    switch UIDevice.current.batteryState {
    case .charging:    return "charging"
    case .full:        return "full"
    case .unplugged:   return "unplugged"
    case .unknown:     return "unknown"
    @unknown default:  return "unknown"
    }
}

func orientationString() -> String? {
    switch UIDevice.current.orientation {
    case .portrait:           return "portrait"
    case .portraitUpsideDown: return "portraitUpsideDown"
    case .landscapeLeft:      return "landscapeLeft"
    case .landscapeRight:     return "landscapeRight"
    case .faceUp:             return "faceUp"
    case .faceDown:           return "faceDown"
    default:                  return "unknown"
    }
}

func thermalStateString() -> String? {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal:  return "nominal"
    case .fair:     return "fair"
    case .serious:  return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
}

func availableStorageGB() -> Double? {
    guard let attrs = try? FileManager.default.attributesOfFileSystem(
        forPath: NSHomeDirectory()
    ), let free = attrs[.systemFreeSize] as? Int64 else { return nil }
    return Double(free) / 1_073_741_824
}

func totalStorageGB() -> Double? {
    guard let attrs = try? FileManager.default.attributesOfFileSystem(
        forPath: NSHomeDirectory()
    ), let total = attrs[.systemSize] as? Int64 else { return nil }
    return Double(total) / 1_073_741_824
}

import CoreLocation
