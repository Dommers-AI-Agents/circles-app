import UIKit

/// Adds photos to a place's library one at a time, each attached as soon as
/// it uploads, so one failure costs one photo. Shared by the place page and
/// Edit Place; the caller owns the progress UI and the summary
/// (PlacePhotoBatchSummary).
enum PlacePhotoBatchUploader {
    typealias Added = (image: UIImage, result: StorageResult)

    /// - progress: (1-based photo now uploading, total), on the main queue
    /// - completion: what was added and how many failed, on the main queue
    static func upload(_ images: [UIImage],
                       to place: Place,
                       progress: @escaping (Int, Int) -> Void,
                       completion: @escaping (_ added: [Added], _ failed: Int) -> Void) {
        let total = images.count
        var added: [Added] = []
        var failed = 0

        func step(_ index: Int) {
            guard index < total else { completion(added, failed); return }
            progress(index + 1, total)
            // Same compression and upload path as Moments
            MediaProcessingService.shared.processPhoto(images[index]) { processed in
                guard case .success(let photo) = processed else {
                    DispatchQueue.main.async { failed += 1; step(index + 1) }
                    return
                }
                MediaStorageService.shared.uploadPhoto(photo, for: place, type: .placePhoto,
                                                       visibility: "public", progress: { _ in }) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let stored): added.append((image: photo.image, result: stored))
                        case .failure: failed += 1
                        }
                        step(index + 1)
                    }
                }
            }
        }
        DispatchQueue.main.async { step(0) }
    }
}
