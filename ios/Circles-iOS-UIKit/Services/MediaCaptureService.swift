import Foundation
import UIKit
import AVFoundation
import Photos
import CoreLocation

// MARK: - Media Capture Types
enum MediaCaptureType {
    case photo
    case video
    case both
}

enum MediaInputSource {
    case camera
    case photoLibrary
}

struct CapturedMedia {
    let type: MediaType
    let image: UIImage?
    let videoURL: URL?
    /// Where and when a photo was taken: from the file's own GPS/EXIF for a
    /// library pick, here and now for a camera shot. Nil when unknown.
    let coordinate: CLLocationCoordinate2D?
    let takenAt: Date?
    
    enum MediaType {
        case photo(UIImage)
        case video(URL)
    }

    init(type: MediaType, image: UIImage?, videoURL: URL?, coordinate: CLLocationCoordinate2D? = nil, takenAt: Date? = nil) {
        self.type = type
        self.image = image
        self.videoURL = videoURL
        self.coordinate = coordinate
        self.takenAt = takenAt
    }
}

// MARK: - Media Capture Service Delegate
protocol MediaCaptureServiceDelegate: AnyObject {
    func mediaCaptureService(_ service: MediaCaptureService, didCapture media: CapturedMedia)
    func mediaCaptureService(_ service: MediaCaptureService, didFailWithError error: Error)
    func mediaCaptureServiceDidCancel(_ service: MediaCaptureService)
}

// MARK: - Media Capture Service
class MediaCaptureService: NSObject {
    
    // MARK: - Properties
    weak var delegate: MediaCaptureServiceDelegate?
    private weak var presentingViewController: UIViewController?
    private var captureType: MediaCaptureType = .both
    
    // MARK: - Public Methods
    
    /// Present media capture options
    func presentCaptureOptions(
        from viewController: UIViewController,
        type: MediaCaptureType = .both,
        sourceView: UIView? = nil
    ) {
        self.presentingViewController = viewController
        self.captureType = type
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        // Camera options
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            if type == .photo || type == .both {
                actionSheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                    self?.presentCamera(for: .photo)
                })
            }
            
            if type == .video || type == .both {
                actionSheet.addAction(UIAlertAction(title: "Record Video", style: .default) { [weak self] _ in
                    self?.presentCamera(for: .video)
                })
            }
        }
        
        // Photo library options
        if type == .photo || type == .both {
            actionSheet.addAction(UIAlertAction(title: "Choose Photo", style: .default) { [weak self] _ in
                self?.checkPhotoLibraryPermission { granted in
                    if granted {
                        self?.presentPhotoLibrary(for: .photo)
                    } else {
                        self?.delegate?.mediaCaptureService(
                            self!,
                            didFailWithError: MediaCaptureError.photoLibraryAccessDenied
                        )
                    }
                }
            })
        }
        
        if type == .video || type == .both {
            actionSheet.addAction(UIAlertAction(title: "Choose Video", style: .default) { [weak self] _ in
                self?.checkPhotoLibraryPermission { granted in
                    if granted {
                        self?.presentPhotoLibrary(for: .video)
                    } else {
                        self?.delegate?.mediaCaptureService(
                            self!,
                            didFailWithError: MediaCaptureError.photoLibraryAccessDenied
                        )
                    }
                }
            })
        }
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.delegate?.mediaCaptureServiceDidCancel(self!)
        })
        
        // Configure for iPad
        if let popover = actionSheet.popoverPresentationController {
            if let sourceView = sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceView.bounds
            } else {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(
                    x: viewController.view.bounds.midX,
                    y: viewController.view.bounds.midY,
                    width: 0,
                    height: 0
                )
            }
        }
        
        viewController.present(actionSheet, animated: true)
    }
    
    /// Present camera directly for specific media type
    func presentCamera(
        from viewController: UIViewController,
        for type: MediaCaptureType
    ) {
        self.presentingViewController = viewController
        self.captureType = type
        
        presentCamera(for: type)
    }
    
    /// Present photo library directly for specific media type
    func presentPhotoLibrary(
        from viewController: UIViewController,
        for type: MediaCaptureType
    ) {
        self.presentingViewController = viewController
        self.captureType = type
        
        checkPhotoLibraryPermission { [weak self] granted in
            if granted {
                self?.presentPhotoLibrary(for: type)
            } else {
                self?.delegate?.mediaCaptureService(
                    self!,
                    didFailWithError: MediaCaptureError.photoLibraryAccessDenied
                )
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func presentCamera(for type: MediaCaptureType) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            delegate?.mediaCaptureService(self, didFailWithError: MediaCaptureError.cameraNotAvailable)
            return
        }
        
        guard let viewController = presentingViewController else { return }

        // The camera subsystem is slow to spin up — show an immediate indicator.
        presentPickerWithWarmupHUD(from: viewController, message: "Opening Camera…") {
            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = .camera
            imagePicker.delegate = self
            imagePicker.allowsEditing = false

            switch type {
            case .photo:
                imagePicker.mediaTypes = ["public.image"]
            case .video:
                imagePicker.mediaTypes = ["public.movie"]
                imagePicker.videoMaximumDuration = 15 // 15 seconds max for consistency with Moments
                imagePicker.videoQuality = .typeHigh
            case .both:
                imagePicker.mediaTypes = ["public.image", "public.movie"]
                imagePicker.videoMaximumDuration = 15
                imagePicker.videoQuality = .typeHigh
            }
            return imagePicker
        }
    }
    
    private func presentPhotoLibrary(for type: MediaCaptureType) {
        guard let viewController = presentingViewController else { return }

        let mediaTypes: [String]
        switch type {
        case .photo: mediaTypes = ["public.image"]
        case .video: mediaTypes = ["public.movie"]
        case .both:  mediaTypes = ["public.image", "public.movie"]
        }

        // The photo library takes a moment to warm up. Show an immediate
        // "Opening Photos…" indicator so the tap doesn't feel dead, then swap
        // in the picker once it's built.
        presentPickerWithWarmupHUD(from: viewController, message: "Opening Photos…") {
            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = .photoLibrary
            imagePicker.delegate = self
            imagePicker.allowsEditing = false
            imagePicker.mediaTypes = mediaTypes
            return imagePicker
        }
    }

    /// Shows a brief loading HUD, builds the (slow-to-init) picker on the next
    /// runloop so the HUD is visible during the warm-up, then dismisses the HUD
    /// and presents the picker.
    private func presentPickerWithWarmupHUD(
        from viewController: UIViewController,
        message: String,
        build: @escaping () -> UIImagePickerController
    ) {
        let hud = AlertPresenter.showLoading(message: message, from: viewController)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let picker = build()
            hud.dismiss(animated: false) {
                viewController.present(picker, animated: true)
            }
        }
    }
    
    private func checkPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        @unknown default:
            completion(false)
        }
    }
}

// MARK: - UIImagePickerController Delegate
extension MediaCaptureService: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
    ) {
        picker.dismiss(animated: true)
        
        if let videoURL = info[.mediaURL] as? URL {
            // Handle video capture
            let media = CapturedMedia(
                type: .video(videoURL),
                image: nil,
                videoURL: videoURL
            )
            delegate?.mediaCaptureService(self, didCapture: media)
            
        } else if let image = info[.originalImage] as? UIImage {
            // Handle photo capture. A UIImage keeps no metadata, so where and
            // when it was taken come from the picked file (the picker's copy
            // of the original keeps its GPS/EXIF) or, for a camera shot, the
            // last known position and now — no location request is made.
            var coordinate: CLLocationCoordinate2D?
            var takenAt: Date?
            if picker.sourceType == .camera {
                coordinate = LocationService.shared.cachedLocation?.coordinate
                takenAt = Date()
            } else {
                if let fileURL = info[.imageURL] as? URL, let data = try? Data(contentsOf: fileURL) {
                    let meta = PhotoMetadataReader.metadata(from: data)
                    coordinate = meta.coordinate
                    takenAt = meta.takenAt
                }
                // The library's own record of the asset, when the app already
                // has Photos access (nil otherwise — it never asks)
                if let asset = info[.phAsset] as? PHAsset {
                    if coordinate == nil, let spot = asset.location?.coordinate, CLLocationCoordinate2DIsValid(spot) { coordinate = spot }
                    if takenAt == nil { takenAt = asset.creationDate }
                }
            }
            let media = CapturedMedia(
                type: .photo(image),
                image: image,
                videoURL: nil,
                coordinate: coordinate,
                takenAt: takenAt
            )
            delegate?.mediaCaptureService(self, didCapture: media)
            
        } else {
            delegate?.mediaCaptureService(self, didFailWithError: MediaCaptureError.noMediaSelected)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        delegate?.mediaCaptureServiceDidCancel(self)
    }
}

// MARK: - Media Capture Errors
enum MediaCaptureError: LocalizedError {
    case cameraNotAvailable
    case photoLibraryAccessDenied
    case noMediaSelected
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .cameraNotAvailable:
            return "Camera is not available on this device"
        case .photoLibraryAccessDenied:
            return "Photo library access is required to select media"
        case .noMediaSelected:
            return "No media was selected"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}