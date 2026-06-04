// MARK: - ScreenStreamManager.swift
// Uses ReplayKit to capture the device screen and delivers JPEG frames
// directly to EmbeddedServer, which fans them out to connected browser clients.
//
// Usage:
//   ScreenStreamManager.shared.start()
//   ScreenStreamManager.shared.stop()
//
// Entitlements / Privacy keys required in Info.plist:
//   NSMicrophoneUsageDescription  (ReplayKit always requests mic permission)

import ReplayKit
import Foundation
import UIKit

public final class ScreenStreamManager: NSObject {

    public static let shared = ScreenStreamManager()

    public var isStreaming: Bool { _isStreaming }
    private var _isStreaming = false

    // Throttle: max frames per second to avoid flooding connected clients
    public var maxFPS: Double = 10
    private var lastFrameTime = Date.distantPast
    private var minFrameInterval: TimeInterval { 1.0 / maxFPS }

    // JPEG quality 0.0-1.0 (lower = smaller payload)
    public var jpegQuality: CGFloat = 0.5

    private let recorder = RPScreenRecorder.shared()
    private let queue = DispatchQueue(label: "com.selfsurveillance.screen", qos: .utility)

    private override init() { super.init() }

    // MARK: - Public API

    public func start() {
        guard !_isStreaming else { return }

        recorder.isMicrophoneEnabled = false
        recorder.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard bufferType == .video, error == nil else { return }
            self?.handleVideoFrame(sampleBuffer)
        }) { [weak self] error in
            if let error = error {
                print("[ScreenStreamManager] Failed to start capture: \(error)")
                self?.logStreamEvent("captureFailed", detail: error.localizedDescription)
            } else {
                self?._isStreaming = true
                self?.logStreamEvent("captureStarted", detail: nil)
            }
        }
    }

    public func stop() {
        guard _isStreaming else { return }
        recorder.stopCapture { [weak self] error in
            self?._isStreaming = false
            self?.logStreamEvent("captureStopped", detail: error?.localizedDescription)
        }
    }

    // MARK: - Frame handling

    private func handleVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= minFrameInterval else { return }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        queue.async { [weak self] in
            guard let self = self else { return }
            guard let jpegData = self.compressFrame(pixelBuffer) else { return }
            EmbeddedServer.shared.broadcastScreenFrame(jpegData)
        }
    }

    private func compressFrame(_ pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        return UIImage(cgImage: cgImage).jpegData(compressionQuality: jpegQuality)
    }

    // MARK: - Logging

    private func logStreamEvent(_ eventType: String, detail: String?) {
        ImmutableLogStore.shared.append(
            source: .systemEvents,
            category: .system,
            eventType: eventType,
            payload: .systemEvent(SystemEventPayload(
                eventType: eventType,
                description: detail,
                version: nil,
                metadata: ["fps": "\(Int(maxFPS))", "quality": "\(jpegQuality)"]
            ))
        )
    }
}
