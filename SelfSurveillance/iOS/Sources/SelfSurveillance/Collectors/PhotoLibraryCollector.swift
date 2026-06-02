// MARK: - PhotoLibraryCollector.swift
// Observes PHPhotoLibrary changes and captures every addition, deletion,
// and modification event including a 128×128 thumbnail.
//
// Deletion capture is specifically important for amnesia use case:
// we log the thumbnail + metadata BEFORE the asset is fully purged,
// using PHPhotoLibraryChangeObserver which fires synchronously with the change.

import Photos
import UIKit

public final class PhotoLibraryCollector: NSObject, PHPhotoLibraryChangeObserver {

    public static let shared = PhotoLibraryCollector()
    private var allAssets: PHFetchResult<PHAsset>?
    private var allAlbums: PHFetchResult<PHAssetCollection>?

    private override init() { super.init() }

    public func start() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard status == .authorized || status == .limited else { return }
            DispatchQueue.main.async {
                self?.setupInitialSnapshot()
                PHPhotoLibrary.shared().register(self!)
            }
        }
    }

    public func stop() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    private func setupInitialSnapshot() {
        let assetOptions = PHFetchOptions()
        assetOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        allAssets = PHAsset.fetchAssets(with: assetOptions)

        let albumOptions = PHFetchOptions()
        allAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: albumOptions
        )
    }

    // MARK: - PHPhotoLibraryChangeObserver

    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let assetResult = allAssets else { return }
        let details = changeInstance.changeDetails(for: assetResult)

        // Inserted assets
        details?.insertedObjects.forEach { asset in
            captureThumbnail(for: asset, eventKind: "added")
        }

        // Removed assets — capture last known metadata; thumbnail already in cache
        details?.removedObjects.forEach { asset in
            captureThumbnail(for: asset, eventKind: "deleted")
        }

        // Changed assets
        details?.changedObjects.forEach { asset in
            captureThumbnail(for: asset, eventKind: "modified")
        }

        // Update snapshot
        if let newResult = details?.fetchResultAfterChanges {
            allAssets = newResult
        }

        // Album changes
        if let albumResult = allAlbums,
           let albumDetails = changeInstance.changeDetails(for: albumResult) {
            albumDetails.insertedObjects.forEach { collection in
                ImmutableLogStore.shared.append(
                    source: .photoLibrary,
                    category: .media,
                    eventType: "albumCreated",
                    payload: .photoEvent(PhotoEventPayload(
                        eventKind: "albumCreated",
                        assetLocalID: collection.localIdentifier,
                        fileName: collection.localizedTitle,
                        mediaType: "album",
                        creationDate: collection.startDate,
                        location: nil,
                        isFavorite: nil,
                        isHidden: nil,
                        albumName: collection.localizedTitle,
                        thumbnailBase64: nil,
                        exifMetadata: nil
                    ))
                )
            }
            albumDetails.removedObjects.forEach { collection in
                ImmutableLogStore.shared.append(
                    source: .photoLibrary,
                    category: .media,
                    eventType: "albumDeleted",
                    payload: .photoEvent(PhotoEventPayload(
                        eventKind: "albumDeleted",
                        assetLocalID: collection.localIdentifier,
                        fileName: collection.localizedTitle,
                        mediaType: "album",
                        creationDate: collection.startDate,
                        location: nil,
                        isFavorite: nil,
                        isHidden: nil,
                        albumName: collection.localizedTitle,
                        thumbnailBase64: nil,
                        exifMetadata: nil
                    ))
                )
            }
            if let newAlbumResult = albumDetails.fetchResultAfterChanges {
                allAlbums = newAlbumResult
            }
        }
    }

    // MARK: - Thumbnail capture

    private func captureThumbnail(for asset: PHAsset, eventKind: String) {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false   // Read local only, never pull from iCloud

        var thumbnailBase64: String? = nil
        let targetSize = CGSize(width: 128, height: 128)

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            if let img = image, let jpegData = img.jpegData(compressionQuality: 0.6) {
                thumbnailBase64 = jpegData.base64EncodedString()
            }
        }

        // Extract EXIF-equivalent metadata from PHAsset
        var mediaTypeStr: String
        switch asset.mediaType {
        case .image:    mediaTypeStr = "image"
        case .video:    mediaTypeStr = "video"
        case .audio:    mediaTypeStr = "audio"
        default:        mediaTypeStr = "unknown"
        }
        if asset.mediaSubtypes.contains(.photoLive) { mediaTypeStr = "livePhoto" }

        var locationStr: String? = nil
        if let loc = asset.location {
            locationStr = "\(loc.coordinate.latitude),\(loc.coordinate.longitude)"
        }

        var exif: [String: String] = [:]
        exif["localIdentifier"] = asset.localIdentifier
        exif["pixelWidth"]      = "\(asset.pixelWidth)"
        exif["pixelHeight"]     = "\(asset.pixelHeight)"
        exif["duration"]        = "\(asset.duration)"
        exif["isBurst"]         = "\(asset.representsBurst)"
        if asset.mediaSubtypes.contains(.photoHDR) { exif["hdr"] = "true" }
        if asset.mediaSubtypes.contains(.videoCinematic) { exif["cinematic"] = "true" }

        ImmutableLogStore.shared.append(
            source: .photoLibrary,
            category: .media,
            eventType: eventKind,
            payload: .photoEvent(PhotoEventPayload(
                eventKind: eventKind,
                assetLocalID: asset.localIdentifier,
                fileName: asset.value(forKey: "filename") as? String,
                mediaType: mediaTypeStr,
                creationDate: asset.creationDate,
                location: locationStr,
                isFavorite: asset.isFavorite,
                isHidden: asset.isHidden,
                albumName: nil,
                thumbnailBase64: thumbnailBase64,
                exifMetadata: exif.isEmpty ? nil : exif
            ))
        )
    }
}
