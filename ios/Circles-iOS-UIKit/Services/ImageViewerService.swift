import UIKit

class ImageViewerService {
    static let shared = ImageViewerService()
    
    private init() {}
    
    /// Present a full-screen image viewer with the given image
    /// - Parameters:
    ///   - image: The UIImage to display
    ///   - from: The presenting view controller
    func presentImage(_ image: UIImage, from viewController: UIViewController) {
        let imageViewer = FullScreenImageViewController(image: image)
        imageViewer.modalPresentationStyle = .overFullScreen
        imageViewer.modalTransitionStyle = .crossDissolve
        
        viewController.present(imageViewer, animated: true)
    }
    
    /// Present a full-screen image viewer with an image from URL
    /// - Parameters:
    ///   - imageURL: The URL string of the image to display
    ///   - from: The presenting view controller
    func presentImageFromURL(_ imageURL: String, from viewController: UIViewController) {
        let imageViewer = FullScreenImageViewController(imageURL: imageURL)
        imageViewer.modalPresentationStyle = .overFullScreen
        imageViewer.modalTransitionStyle = .crossDissolve
        
        viewController.present(imageViewer, animated: true)
    }
    
    /// Present a full-screen image viewer with the image from an ImageView
    /// - Parameters:
    ///   - imageView: The UIImageView containing the image to display
    ///   - from: The presenting view controller
    func presentImageFromImageView(_ imageView: UIImageView, from viewController: UIViewController) {
        guard let image = imageView.image else {
            print("⚠️ ImageViewerService: No image found in ImageView")
            return
        }
        
        presentImage(image, from: viewController)
    }
    
    /// Add a tap gesture to an ImageView to enable full-screen viewing
    /// - Parameters:
    ///   - imageView: The UIImageView to make tappable
    ///   - viewController: The view controller that will present the full-screen viewer
    func makeImageViewTappable(_ imageView: UIImageView, from viewController: UIViewController) {
        imageView.isUserInteractionEnabled = true
        
        // Remove any existing tap gestures to avoid duplicates
        imageView.gestureRecognizers?.removeAll { $0 is UITapGestureRecognizer }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(imageViewTapped(_:)))
        tapGesture.numberOfTapsRequired = 1
        imageView.addGestureRecognizer(tapGesture)
        
        // Store the presenting view controller in the gesture recognizer
        // We'll use objc_setAssociatedObject to associate the view controller with the gesture
        objc_setAssociatedObject(tapGesture, &AssociatedKeys.viewController, viewController, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    /// Add a tap gesture to an ImageView to enable full-screen viewing with a specific image URL
    /// - Parameters:
    ///   - imageView: The UIImageView to make tappable
    ///   - imageURL: The URL string of the full-resolution image to display
    ///   - viewController: The view controller that will present the full-screen viewer
    func makeImageViewTappableWithURL(_ imageView: UIImageView, imageURL: String, from viewController: UIViewController) {
        imageView.isUserInteractionEnabled = true
        
        // Remove any existing tap gestures to avoid duplicates
        imageView.gestureRecognizers?.removeAll { $0 is UITapGestureRecognizer }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(imageViewWithURLTapped(_:)))
        tapGesture.numberOfTapsRequired = 1
        imageView.addGestureRecognizer(tapGesture)
        
        // Store both the presenting view controller and image URL
        objc_setAssociatedObject(tapGesture, &AssociatedKeys.viewController, viewController, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(tapGesture, &AssociatedKeys.imageURL, imageURL, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    @objc private func imageViewTapped(_ gesture: UITapGestureRecognizer) {
        guard let imageView = gesture.view as? UIImageView,
              let viewController = objc_getAssociatedObject(gesture, &AssociatedKeys.viewController) as? UIViewController else {
            return
        }
        
        presentImageFromImageView(imageView, from: viewController)
    }
    
    @objc private func imageViewWithURLTapped(_ gesture: UITapGestureRecognizer) {
        guard let viewController = objc_getAssociatedObject(gesture, &AssociatedKeys.viewController) as? UIViewController,
              let imageURL = objc_getAssociatedObject(gesture, &AssociatedKeys.imageURL) as? String else {
            return
        }
        
        presentImageFromURL(imageURL, from: viewController)
    }
}

// MARK: - Associated Object Keys
private struct AssociatedKeys {
    static var viewController = "viewController"
    static var imageURL = "imageURL"
}