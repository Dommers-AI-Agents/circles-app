import UIKit
import PhotosUI
import MapKit

// MARK: - Fill from a photo

/// Add Place's "From Photo": pick photos taken at the place (even with no
/// signal at the time), and the form fills with the business Apple Maps lists
/// where they were taken. The first photo becomes the place's photo; the rest
/// join its library once it's saved (PendingPlacePhotos).
extension AddPlaceViewController {
    func installFromPhotoButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "From Photo", image: UIImage(systemName: "photo.on.rectangle"),
            primaryAction: UIAction { [weak self] _ in self?.fromPhotoTapped() })
    }

    private func fromPhotoTapped() {
        let helper = PhotoFillPicker(form: self)
        photoFillPicker = helper   // kept alive while the picker is up
        let picker = PHPickerViewController(configuration: PhotoMetadataReader.pickerConfiguration(limit: 10))
        picker.delegate = helper
        present(picker, animated: true)
    }

    /// The picked photo as the form's own photo (same path as Add Photo).
    func useFormPhoto(_ image: UIImage) {
        selectedImage = image
        photoImageView.image = image
        photoImageView.isHidden = false
        removePhotoButton.isHidden = false
        addPhotoButton.isHidden = true
        photosWereAutoPopulated = false
        uploadedPhotoUrls.removeAll()
        downloadedGoogleImage = nil
        downloadedLookAroundImage = nil
        if let data = image.jpegData(compressionQuality: 0.8) {
            uploadImageData(data) { [weak self] url in
                guard let self, let url, !self.uploadedPhotoUrls.contains(url) else { return }
                self.uploadedPhotoUrls.append(url)
            }
        }
    }
}

final class PhotoFillPicker: NSObject, PHPickerViewControllerDelegate {
    private weak var form: AddPlaceViewController?

    init(form: AddPlaceViewController) { self.form = form }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let form, !results.isEmpty else { return }
        let loading = AlertPresenter.showLoading(message: "Finding where these were taken…", from: form)
        PhotoMetadataReader.load(results) { [weak self] picked in
            guard let self, let form = self.form else { loading.dismiss(animated: true); return }
            let groups = PhotoPlaceGrouper.group(picked.enumerated().map {
                PhotoPlaceGrouper.Fix(id: $0.offset, coordinate: $0.element.coordinate, takenAt: $0.element.takenAt)
            })
            guard let group = groups.first(where: { $0.center != nil }), let center = group.center else {
                loading.dismiss(animated: true) {
                    AlertPresenter.showError(title: "No location in these photos",
                                             message: "They don't say where they were taken (the photo's location may be turned off). Search for the place instead.",
                                             from: form)
                }
                return
            }
            let images = group.photoIds.map { picked[$0].image }
            NearbyPOILookup.pointsOfInterest(near: center, radius: PhotoPlaceRanker.poiRadiusMeters) { items in
                loading.dismiss(animated: true) {
                    let pois = items.map { PhotoPlaceRanker.POI(name: $0.name ?? "", coordinate: $0.placemark.coordinate,
                                                                 isResidential: AppleMapItemFormFill.isResidentialAddress(name: $0.name)) }
                    let pick = PhotoPlaceRanker.rank(center: center, saved: [], pois: pois).first
                    form.enableManualEntry()
                    if case .poi(let index, _) = pick {
                        form.fillFormWithMapItem(items[index])
                    } else {
                        // Nothing listed there: a pin where the photos were taken
                        form.handleManualLocationTap(at: center)
                    }
                    form.mapView.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 500, longitudinalMeters: 500), animated: true)
                    form.useFormPhoto(images[0])
                    PendingPlacePhotos.shared.expect(Array(images.dropFirst()), near: center)
                    if groups.filter({ $0.center != nil }).count > 1 {
                        AlertPresenter.showSuccess(title: "Photos from more than one place",
                                                   message: "Filled in the first place. Use Add Place → From photos on the home screen to save each of them.",
                                                   from: form)
                    }
                    self.form?.photoFillPicker = nil
                }
            }
        }
    }
}
