// MARK: - ScreenStreamManager.swift
// Uses ReplayKit to capture the device screen and streams JPEG frames to the
// backend server over a WebSocket connection.
//
// Each frame is sent as a binary WebSocket message containing a raw JPEG.
// The server broadcasts those frames to connected Android viewers.
//
// Usage:
//   ScreenStreamManager.shared.start(serverURL: "ws://192.168.1.x:3000/screen/publish")
//   ScreenStreamManager.shared.stop()
//
// Entitlements / Privacy keys required in Info.plist:
//   NSMicrophoneUsageDescription  (ReplayKit always requests mic permission)

import ReplayKit
import Foundation

public final class ScreenStreamManager: NSObject {

    public static let shared = ScreenStreamManager()

    public var isStreaming: Bool { _isStreaming }
    private var _isStreaming = false

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var serverURL: URL?

    // Throttle: max frames per second to avoid flooding the network
    public var maxFPS: Double = 10
    private var lastFrameTime = Date.distantPast
    private var minFrameInterval: TimeInterval { 1.0 / maxFPS }

    // JPEG quality 0.0-1.0 (lower = smaller payload)
    public var jpegQuality: CGFloat = 0.5

    private let recorder = RPScreenRecorder.shared()
    private let queue = DispatchQueue(label: "com.selfsurveillance.screen", qos: .utility)

    private override init() { super.init() }

    // MARK: - Public API

    public func start(serverURL: String) {
        guard !_isStreaming else { return }
        guard let url = URL(string: serverURL) else { return }

        self.serverURL = url
        connectWebSocket(url: url)

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
            self?.webSocket?.cancel(with: .goingAway, reason: nil)
            self?.webSocket = nil
            self?.logStreamEvent("captureStopped",
                detail: error?.localizedDescription)
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
            self.sendFrame(jpegData)
        }
    }

    private func compressFrame(_ pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: jpegQuality)
    }

    // MARK: - WebSocket

    private func connectWebSocket(url: URL) {
        let config  = URLSessionConfiguration.default
        session     = URLSession(configuration: config)
        webSocket   = session?.webSocketTask(with: url)
        webSocket?.resume()
        receiveLoop()
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("[ScreenStreamManager] WebSocket error: \(error)")
                // Attempt reconnect after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard let self = self, self._isStreaming, let url = self.serverURL else { return }
                    self.connectWebSocket(url: url)
                }
            case .success:
                self?.receiveLoop()
            }
        }
    }

    private func sendFrame(_ data: Data) {
        guard webSocket != nil else { return }
        webSocket?.send(.data(data)) { error in
            if let error = error {
                print("[ScreenStreamManager] Send error: \(error)")
            }
        }
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

import UIKit  // for UIImage.jpegData
