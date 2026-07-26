import UIKit
import MapKit
import CoreLocation
import PhotosUI

// Photo picker and gesture-recognizer delegates for AddPlaceViewController. Extracted from the main controller (Wave 4).

// MARK: - UIGestureRecognizerDelegate

extension AddPlaceViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Handle map tap gesture: always receive it. POI/annotation detection
        // via hitTest is unreliable (MKMapView is composed of internal subviews),
        // so instead the manual-tap action is DELAYED and gets cancelled by
        // didSelect when the same tap selected a POI or annotation.
        if gestureRecognizer is UITapGestureRecognizer && gestureRecognizer.view == mapView {
            // Still skip taps that land on an existing annotation view - the
            // map handles those synchronously via selection
            let location = touch.location(in: mapView)
            for annotation in mapView.annotations {
                if mapView.view(for: annotation) != nil {
                    let annotationPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
                    let annotationRect = CGRect(x: annotationPoint.x - 22, y: annotationPoint.y - 22, width: 44, height: 44)
                    if annotationRect.contains(location) {
                        Logger.debug("🚫 Tap on annotation detected, allowing map to handle it")
                        return false
                    }
                }
            }
            return true
        }
        
        // Handle circle dropdown tap
        let location = touch.location(in: view)
        let circleDropdownFrame = circleDropdownTableView.convert(circleDropdownTableView.bounds, to: view)
        let circleButtonFrame = circleButton.convert(circleButton.bounds, to: view)
        
        if circleDropdownFrame.contains(location) || circleButtonFrame.contains(location) {
            return false
        }
        
        // Handle category dropdown tap
        let categoryDropdownFrame = categoryDropdownTableView.convert(categoryDropdownTableView.bounds, to: view)
        let categoryButtonFrame = categoryButton.convert(categoryButton.bounds, to: view)
        
        if categoryDropdownFrame.contains(location) || categoryButtonFrame.contains(location) {
            return false
        }
        
        return isCategoryDropdownVisible || isCircleDropdownVisible
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow map's internal gesture recognizers to work alongside our tap gesture
        if gestureRecognizer.view == mapView || otherGestureRecognizer.view == mapView {
            Logger.debug("🤝 Allowing simultaneous gesture recognition on map")
            return true
        }
        return false
    }
}

// MARK: - PHPickerViewControllerDelegate

extension AddPlaceViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        
        guard let result = results.first else { return }
        
        if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.selectedImage = image
                        self?.photoImageView.image = image
                        self?.photoImageView.isHidden = false
                        self?.removePhotoButton.isHidden = false
                        self?.addPhotoButton.isHidden = true
                        
                        // Clear pre-uploaded photos since user selected a new one
                        self?.uploadedPhotoUrls.removeAll()
                        self?.downloadedGoogleImage = nil
                        self?.downloadedLookAroundImage = nil
                        
                        // Pre-upload the manually selected photo
                        Logger.debug("📸 Pre-uploading manually selected photo...")
                        if let imageData = image.jpegData(compressionQuality: 0.8) {
                            self?.uploadImageData(imageData) { uploadedUrl in
                                if let url = uploadedUrl {
                                    // Check for duplicates before appending
                                    if !(self?.uploadedPhotoUrls.contains(url) ?? false) {
                                        self?.uploadedPhotoUrls.append(url)
                                        Logger.debug("✅ Manual photo pre-uploaded: \(url)")
                                    } else {
                                        Logger.debug("⚠️ Skipping duplicate photo URL: \(url)")
                                    }
                                } else {
                                    Logger.debug("❌ Failed to pre-upload manual photo")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
