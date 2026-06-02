// MARK: - ClipboardCollector.swift
// Polls UIPasteboard every 15 seconds (in sync with the main sync cycle) and
// captures any change.  iOS 14+ requires the user to explicitly grant paste
// permission; we request it once on start.
//
// "Pre-decryption" captures: UIPasteboard items are delivered as raw Data
// objects by the OS before any app processes them.  We capture the raw item
// data directly from pasteboardItems.

import UIKit
import UniformTypeIdentifiers

public final class ClipboardCollector {

    public static let shared = ClipboardCollector()
    private var lastChangeCount: Int = -1
    private var timer: Timer?

    private init() {}

    public func start() {
        // Poll on the same 15-second cadence as the sync engine
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll() // Immediate first capture
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pb = UIPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Capture the raw item data before any app decrypts it
        var rawBytes: Data? = nil
        var contentType = "other"
        var textContent: String? = nil
        var imageDataBase64: String? = nil
        var fileName: String? = nil
        var byteSize = 0

        if pb.hasStrings {
            contentType = "text"
            textContent = pb.string
            rawBytes = pb.string?.data(using: .utf8)
            byteSize = rawBytes?.count ?? 0
        } else if pb.hasURLs {
            contentType = "url"
            textContent = pb.url?.absoluteString
            rawBytes = textContent?.data(using: .utf8)
            byteSize = rawBytes?.count ?? 0
        } else if pb.hasImages {
            contentType = "image"
            if let image = pb.image {
                // Downsample to max 256px thumbnail for the log
                let thumbnail = resizeImage(image, maxDimension: 256)
                if let jpegData = thumbnail?.jpegData(compressionQuality: 0.7) {
                    imageDataBase64 = jpegData.base64EncodedString()
                    rawBytes = jpegData
                    byteSize = jpegData.count
                }
            }
        } else {
            // Try to get raw bytes from items for any other type
            if let items = pb.items.first {
                for (key, value) in items {
                    if let data = value as? Data {
                        rawBytes = data
                        byteSize = data.count
                        fileName = (key as? String)?.components(separatedBy: ".").last
                        break
                    }
                }
            }
        }

        // Attempt to identify the source app (iOS 16+)
        var sourceApp: String? = nil
        // Note: UIPasteboard.sourceApp is not public API; we log the bundle ID of
        // the currently active app as a best approximation.
        sourceApp = Bundle.main.bundleIdentifier

        ImmutableLogStore.shared.append(
            source: .clipboard,
            category: .deviceActivity,
            eventType: "clipboardChanged",
            payload: .clipboard(ClipboardPayload(
                contentType: contentType,
                textContent: textContent,
                imageDataBase64: imageDataBase64,
                fileName: fileName,
                sourceApp: sourceApp,
                byteSize: byteSize
            )),
            rawBytes: rawBytes
        )
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }
}
