import UIKit
import PhotosUI

/// "Ordered for delivery? Send your receipt" (2026-11-06): the customer picks
/// a photo or screenshot of a DoorDash / Uber Eats receipt, the phone reads it
/// (ReceiptReader, on-device), shows what it found, and sends it to the store
/// for points — right away when the store is Automatic and it checks out.
final class SendReceiptViewController: BaseViewController {
    private let venueId: String
    private let venueName: String
    /// The store's setting: "approve" or "auto"
    private let mode: String?
    var onEarned: (() -> Void)?

    private var image: UIImage?
    private var reading: ReceiptReading?

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let intro = UILabel()
    private let preview = UIImageView()
    private let checksStack = UIStackView()
    private let note = UILabel()
    private lazy var screenshotButton = UIButton.primaryButton(title: "Choose a screenshot or photo")
    private lazy var cameraButton = UIButton.secondaryButton(title: "Take a photo")
    private lazy var sendButton = UIButton.primaryButton(title: "Send to store")

    init(venueId: String, venueName: String, mode: String?) {
        self.venueId = venueId
        self.venueName = venueName
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        title = "Delivery receipt"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))

        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32)
        ])

        intro.text = "Ordered \(venueName) through DoorDash, Uber Eats or another app? Send the receipt and get the same points as a visit. One a day, within a week of the order."
        intro.font = .systemFont(ofSize: 15)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0

        preview.contentMode = .scaleAspectFit
        preview.clipsToBounds = true
        preview.layer.cornerRadius = 12
        preview.backgroundColor = .secondarySystemBackground
        preview.isHidden = true
        preview.heightAnchor.constraint(equalToConstant: 280).isActive = true

        checksStack.axis = .vertical
        checksStack.spacing = 8
        note.font = .systemFont(ofSize: 14)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0

        screenshotButton.addTarget(self, action: #selector(screenshotTapped), for: .touchUpInside)
        cameraButton.addTarget(self, action: #selector(cameraTapped), for: .touchUpInside)
        cameraButton.isHidden = !UIImagePickerController.isSourceTypeAvailable(.camera)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.isHidden = true

        [intro, preview, checksStack, note, sendButton, screenshotButton, cameraButton].forEach(stack.addArrangedSubview)
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func screenshotTapped() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func cameraTapped() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }

    private func use(_ picked: UIImage) {
        image = picked
        reading = nil
        preview.image = picked
        preview.isHidden = false
        sendButton.isHidden = true
        note.text = "Reading the receipt…"
        checksStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        ReceiptTextRecognizer.lines(in: picked) { [weak self] lines in
            guard let self, self.image === picked else { return }
            self.show(ReceiptReader.read(lines: lines, venueName: self.venueName))
        }
    }

    private func show(_ reading: ReceiptReading) {
        self.reading = reading
        let checks = ReceiptCopy.checks(reading, venueName: venueName)
        checks.forEach { check in
            let label = UILabel()
            label.numberOfLines = 0
            label.font = .systemFont(ofSize: 15)
            let symbol = check.ok ? "checkmark.circle.fill" : "xmark.circle.fill"
            let tint: UIColor = check.ok ? .systemGreen : .systemRed
            let text = NSMutableAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: symbol)?.withTintColor(tint) ?? UIImage()))
            text.append(NSAttributedString(string: "  " + check.text))
            label.attributedText = text
            checksStack.addArrangedSubview(label)
        }
        if let app = reading.deliveryApp {
            let label = UILabel()
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
            label.text = "From \(app)"
            checksStack.addArrangedSubview(label)
        }
        let tooOld = ReceiptReader.isTooOld(reading.orderDate)
        note.text = tooOld
            ? "Receipts earn points for a week after the order."
            : ReceiptCopy.sendNote(mode: mode, venueName: venueName, allOK: checks.allSatisfy(\.ok))
        sendButton.isHidden = tooOld
        screenshotButton.setTitle("Choose a different one", for: .normal)
    }

    @objc private func sendTapped() {
        guard let image, let reading, let jpeg = Self.jpeg(image) else { return }
        sendButton.isEnabled = false
        let loading = AlertPresenter.showLoading(from: self)
        RewardsService.shared.sendReceipt(venueId: venueId, imageBase64: jpeg.base64EncodedString(), reading: reading) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    self.sendButton.isEnabled = true
                    switch result {
                    case .success(let sent):
                        let words = ReceiptCopy.sentMessage(sent, venueName: self.venueName)
                        if sent.status == "approved" { self.onEarned?() }
                        AlertPresenter.showSuccess(title: words.title, message: words.message, from: self) { [weak self] in
                            self?.dismiss(animated: true)
                        }
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    /// At most 2,000 px on the long edge: enough to read, small to send
    private static func jpeg(_ image: UIImage) -> Data? {
        ImageUpload.jpeg(image, maxPixels: 2000, quality: 0.75, maxBytes: .max)
    }
}

extension SendReceiptViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let picked = object as? UIImage else { return }
            DispatchQueue.main.async { self?.use(picked) }
        }
    }
}

extension SendReceiptViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let picked = info[.originalImage] as? UIImage { use(picked) }
    }
}
