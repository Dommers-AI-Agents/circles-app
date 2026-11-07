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

    /// Says what it does before the picker opens (Wes, 2026-11-07: tapping
    /// the icon should explain itself).
    private func fromPhotoTapped() {
        AlertPresenter.showConfirmation(
            title: "Fill this in from a photo",
            message: "Pick a photo you took at the place. FavCircles reads where it was taken and fills in the business there, with your photo as its picture.\n\nTo add lots of places from your photos at once, use Add places from your photos.",
            confirmTitle: "Choose a Photo",
            cancelTitle: "Not Now",
            from: self,
            onConfirm: { [weak self] in self?.presentPhotoFillPicker() })
    }

    private func presentPhotoFillPicker() {
        let helper = PhotoFillPicker(form: self)
        photoFillPicker = helper   // kept alive while it works
        let picker = PHPickerViewController(configuration: PhotoMetadataReader.pickerConfiguration(limit: 10))
        picker.delegate = helper
        present(picker, animated: true)
    }

    /// Stops a photo fill still working: the person picked a place another
    /// way, or tapped Cancel. Its late answer is ignored.
    func cancelPhotoFill() {
        photoFillPicker = nil
        hidePhotoFillStatus()
    }

    /// A bar over the map while the photo is read and looked up. It doesn't
    /// block the screen: search or tap the map meanwhile, or Cancel.
    func showPhotoFillStatus() {
        hidePhotoFillStatus()
        mapTapHint.isHidden = true
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .white
        spinner.startAnimating()
        let label = UILabel()
        label.text = "Finding where your photo was taken…"
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.numberOfLines = 2
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let cancel = UIButton.smallActionButton(title: "Cancel", style: .secondary)
        cancel.addAction(UIAction { [weak self] _ in self?.cancelPhotoFill() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [spinner, label, cancel])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        let bar = UIView()
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        bar.layer.cornerRadius = 16
        bar.layer.cornerCurve = .continuous
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        mapContainer.addSubview(bar)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            bar.topAnchor.constraint(equalTo: mapContainer.topAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: mapContainer.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: mapContainer.trailingAnchor, constant: -12)
        ])
        photoFillStatusView = bar
    }

    func hidePhotoFillStatus() {
        photoFillStatusView?.removeFromSuperview()
        photoFillStatusView = nil
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

    /// Apple Maps gets this long to answer before the photo's spot is used
    static let lookupTimeout: TimeInterval = 12

    /// Still the fill the form is waiting for (not cancelled or replaced)
    private var isCurrent: Bool { form?.photoFillPicker === self }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let form, !results.isEmpty else { form?.photoFillPicker = nil; return }
        // A bar over the map, not a blocking alert: an alert put up while the
        // picker was still closing could miss its dismissal and spin forever
        // (Wes, 2026-11-07)
        form.showPhotoFillStatus()
        PhotoMetadataReader.load(results) { [weak self] picked in
            guard let self, self.isCurrent, let form = self.form else { return }
            let groups = PhotoPlaceGrouper.group(picked.enumerated().map {
                PhotoPlaceGrouper.Fix(id: $0.offset, coordinate: $0.element.coordinate, takenAt: $0.element.takenAt,
                                  accuracy: $0.element.accuracy)
            })
            guard let group = groups.first(where: { $0.center != nil }), let center = group.center else {
                form.cancelPhotoFill()
                AlertPresenter.showError(title: picked.isEmpty ? "Couldn't open that photo" : "No location in this photo",
                                         message: picked.isEmpty
                                            ? "It may still be downloading from iCloud. Try again in a moment, or search for the place instead."
                                            : "It doesn't say where it was taken (the photo's location may be turned off). Search for the place instead.",
                                         from: form)
                return
            }
            let images = group.photoIds.map { picked[$0].image }
            var answered = false
            let finish: ([MKMapItem]) -> Void = { [weak self] items in
                guard !answered else { return }
                answered = true
                guard let self, self.isCurrent, let form = self.form else { return }
                self.apply(items, center: center, images: images, placeCount: groups.filter { $0.center != nil }.count, to: form)
            }
            // The bulk photo flow's ranking: cafés, restaurants and venues
            // ahead of the office or shop next door, reach set by how sure
            // the photo's location is
            NearbyPOILookup.savablePlacesResult(near: center, uncertainty: group.uncertainty) { result in
                finish((try? result.get()) ?? [])
            }
            // No answer (offline, throttled): a pin where the photo was taken
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.lookupTimeout) { finish([]) }
        }
    }

    private func apply(_ items: [MKMapItem], center: CLLocationCoordinate2D, images: [UIImage],
                       placeCount: Int, to form: AddPlaceViewController) {
        form.cancelPhotoFill()
        form.mapView.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 500, longitudinalMeters: 500), animated: true)
        // Fill first, then the photo: a fill brings its own picture, and the
        // photo you picked should win
        let commit: (MKMapItem?) -> Void = { [weak form] item in
            guard let form else { return }
            form.enableManualEntry()
            if let item {
                form.fillFormWithMapItem(item)
            } else {
                // Nothing listed there: a pin where the photo was taken
                form.handleManualLocationTap(at: center)
            }
            if let first = images.first { form.useFormPhoto(first) }
            PendingPlacePhotos.shared.expect(Array(images.dropFirst()), near: center)
            if placeCount > 1 {
                AlertPresenter.showSuccess(title: "Photos from more than one place",
                                           message: "Filled in the first place. Use Add places from your photos to save each of them.",
                                           from: form)
            }
        }
        switch PhotoFillChoices.decide(candidateCount: items.count) {
        case .pin:
            commit(nil)
        case .fill(let index):
            commit(items[index])
        case .ask(let count):
            var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = items.prefix(count).map { item in
                (PhotoFillChoices.rowTitle(name: item.name ?? "", kind: PhotoPlaceKind.label(item)), .default, { commit(item) })
            }
            actions.append((PhotoFillChoices.somewhereElse, .default, { commit(nil) }))
            AlertPresenter.showActionSheet(title: PhotoFillChoices.title, message: PhotoFillChoices.message,
                                           actions: actions, from: form, sourceView: form.mapContainer)
        }
    }
}
