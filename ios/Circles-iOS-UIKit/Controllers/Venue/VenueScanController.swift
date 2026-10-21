import UIKit
import PhotosUI

/// "Scan your menu / hours sign / flyer" (2026-10-20): takes or picks the
/// photo(s), shrinks them, sends them to POST /rewards/venues/:id/scan and
/// hands back the draft. The screen that owns it opens its editor on the
/// draft; nothing is saved by a scan. Business only (the caller gates).
/// Hold a strong reference while it runs.
final class VenueScanController: NSObject {
    private let venueId: String
    private let kind: VenueScanKind
    private weak var presenter: UIViewController?
    private var photos: [Data] = []
    private var finish: ((Result<Any, APIError>) -> Void)?
    /// Called with the raw response so each screen decodes its own draft
    private var run: (([Data], @escaping (Result<Any, APIError>) -> Void) -> Void)?

    /// The long edge sent; the server reads at 2,000 px
    static let longEdge: CGFloat = 2000

    init(venueId: String, kind: VenueScanKind, presenter: UIViewController) {
        self.venueId = venueId
        self.kind = kind
        self.presenter = presenter
    }

    /// Picks the photo(s), scans, and returns the typed draft
    func start<Draft: Decodable>(_ type: Draft.Type, sourceView: UIView? = nil,
                                 completion: @escaping (Result<VenueScanResponse<Draft>, APIError>) -> Void) {
        let venueId = self.venueId
        let kind = self.kind
        run = { images, done in
            RewardsService.shared.scanVenue(venueId: venueId, kind: kind, images: images) { (result: Result<VenueScanResponse<Draft>, APIError>) in
                done(result.map { $0 as Any })
            }
        }
        finish = { result in
            completion(result.map { $0 as! VenueScanResponse<Draft> })
        }
        chooseSource(sourceView: sourceView)
    }

    // MARK: - Photos

    private var whatToShoot: String {
        switch kind {
        case .menu: return "Photograph each page of your menu straight on, in good light. Up to 4 pages."
        case .hours: return "Photograph the hours on your door or window."
        case .flyer: return "Photograph the flyer, poster or specials board."
        }
    }

    private func chooseSource(sourceView: UIView?) {
        guard let presenter else { return }
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = []
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            actions.append((title: "Take a photo", style: .default, handler: { [weak self] in self?.openCamera() }))
        }
        actions.append((title: kind.maxPhotos > 1 ? "Choose photos" : "Choose a photo", style: .default,
                        handler: { [weak self] in self?.openLibrary() }))
        AlertPresenter.showActionSheet(title: nil, message: whatToShoot, actions: actions, from: presenter, sourceView: sourceView)
    }

    private func openCamera() {
        guard let presenter else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func openLibrary() {
        guard let presenter else { return }
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = max(1, kind.maxPhotos - photos.count)
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    /// After a camera shot of a menu page: another page, or read it now
    private func askForMorePages() {
        guard let presenter else { return }
        guard kind == .menu, photos.count < kind.maxPhotos else { return send() }
        AlertPresenter.showConfirmation(
            title: "Page \(photos.count) added",
            message: "Does your menu have another page?",
            confirmTitle: "Add a page",
            cancelTitle: "Read my menu",
            from: presenter,
            onConfirm: { [weak self] in self?.openCamera() },
            onCancel: { [weak self] in self?.send() }
        )
    }

    private func add(_ image: UIImage) {
        guard photos.count < kind.maxPhotos, let data = Self.prepared(image) else { return }
        photos.append(data)
    }

    /// Upright, ≤2,000 px on the long edge, JPEG 0.8 (a menu page ~400–900 KB)
    static func prepared(_ image: UIImage) -> Data? {
        let size = image.size
        let scale = min(1, longEdge / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    /// What to tell the owner when a scan fails: the server's words (the
    /// daily limit, "not available right now", a bad photo) or a fallback
    static func message(for error: APIError) -> String {
        error.serverMessage ?? "Couldn\u{2019}t read that photo. Try again, or fill it in by hand."
    }

    // MARK: - Scan

    private func send() {
        guard let presenter, !photos.isEmpty, let run else { return }
        let loading = AlertPresenter.showLoading(message: kind.readingMessage, from: presenter)
        let images = photos
        photos = []
        run(images) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) { self?.finish?(result) }
            }
        }
    }
}

extension VenueScanController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        picker.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            if let image { self.add(image) }
            guard !self.photos.isEmpty else { return }
            self.askForMorePages()
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { [weak self] in
            // Cancelling after some pages still reads the ones taken
            if let self, !self.photos.isEmpty { self.send() }
        }
    }
}

extension VenueScanController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        let group = DispatchGroup()
        var images: [Int: UIImage] = [:]
        let lock = NSLock()
        for (index, result) in results.enumerated() where result.itemProvider.canLoadObject(ofClass: UIImage.self) {
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage { lock.lock(); images[index] = image; lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            // In the order picked (page 1 first)
            images.keys.sorted().compactMap { images[$0] }.forEach(self.add)
            if self.photos.isEmpty {
                if let presenter = self.presenter { AlertPresenter.showError(message: "Those photos couldn\u{2019}t be opened. Try another.", from: presenter) }
                return
            }
            self.send()
        }
    }
}
