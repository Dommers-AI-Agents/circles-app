import Foundation
import UIKit
import AVFoundation
import Photos

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
    
    enum MediaType {
        case photo(UIImage)
        case video(URL)
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
        
        viewController.present(imagePicker, animated: true)
    }
    
    private func presentPhotoLibrary(for type: MediaCaptureType) {
        guard let viewController = presentingViewController else { return }
        
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .photoLibrary
        imagePicker.delegate = self
        imagePicker.allowsEditing = false
        
        switch type {
        case .photo:
            imagePicker.mediaTypes = ["public.image"]
        case .video:
            imagePicker.mediaTypes = ["public.movie"]
        case .both:
            imagePicker.mediaTypes = ["public.image", "public.movie"]
        }
        
        viewController.present(imagePicker, animated: true)
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
            // Handle photo capture
            let media = CapturedMedia(
                type: .photo(image),
                image: image,
                videoURL: nil
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