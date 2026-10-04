import UIKit

/// Adds photos to a place's library one at a time, each attached as soon as
/// it uploads. A photo that can't go up now (no signal, a dropped request)
/// is handed to PlacePhotoOutbox, which adds it when there's a connection —
/// it is never lost. Shared by the place page, Edit Place and "From photos";
/// the caller owns the progress UI and the summary (PlacePhotoBatchSummary).
enum PlacePhotoBatchUploader {
    typealias Added = (image: UIImage, result: StorageResult)

    /// - progress: (1-based photo now uploading, total), on the main queue
    /// - completion: what was added now, and how many are waiting in the
    ///   outbox to be added once there's a signal, on the main queue
    static func upload(_ images: [UIImage],
                       to place: Place,
                       progress: @escaping (Int, Int) -> Void,
                       completion: @escaping (_ added: [Added], _ failed: Int) -> Void) {
        let total = images.count
        var added: [Added] = []
        var failed = 0
        var waiting: [UIImage] = []

        // No signal at all: straight to the outbox rather than waiting for
        // every request to time out
        guard NetworkMonitor.shared.isConnected else {
            PlacePhotoOutbox.shared.add(images, to: place)
            DispatchQueue.main.async { completion([], total) }
            return
        }

        func step(_ index: Int) {
            guard index < total else {
                if !waiting.isEmpty { PlacePhotoOutbox.shared.add(waiting, to: place) }
                completion(added, failed)
                return
            }
            progress(index + 1, total)
            // Same compression and upload path as Moments
            MediaProcessingService.shared.processPhoto(images[index]) { processed in
                guard case .success(let photo) = processed else {
                    DispatchQueue.main.async { failed += 1; waiting.append(images[index]); step(index + 1) }
                    return
                }
                MediaStorageService.shared.uploadPhoto(photo, for: place, type: .placePhoto,
                                                       visibility: "public", progress: { _ in }) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let stored): added.append((image: photo.image, result: stored))
                        case .failure: failed += 1; waiting.append(images[index])
                        }
                        step(index + 1)
                    }
                }
            }
        }
        DispatchQueue.main.async { step(0) }
    }
}
