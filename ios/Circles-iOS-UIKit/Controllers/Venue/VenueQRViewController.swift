import UIKit
import CoreImage

/// Full-screen display of the venue's scan-to-save window QR (free owner
/// tier). Renders the exact URL encoded in the printed sticker, so scanning
/// the phone screen behaves identically to scanning the physical sticker.
class VenueQRViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let venueName: String
    private let stickerUrl: String
    private let screenTitle: String
    private let caption: String
    /// Which code this is, and the store it belongs to: together they unlock
    /// the print-ready PDFs (sign, table tent, counter card). Without a venue
    /// id the screen can still share its image.
    private let kind: VenuePrintKind
    private let venueId: String?

    /// Defaults describe the window sticker; the super-user store page reuses
    /// this screen for the register card with its own title and caption.
    init(
        venueName: String,
        stickerUrl: String,
        screenTitle: String = "Scan-to-Save QR",
        caption: String = "Customers scan this to save your place and start earning points. Display it in your window or share it anywhere.",
        kind: VenuePrintKind = .window,
        venueId: String? = nil
    ) {
        self.venueName = venueName
        self.stickerUrl = stickerUrl
        self.screenTitle = screenTitle
        self.caption = caption
        self.kind = kind
        self.venueId = venueId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Elements

    private let qrContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 16
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let qrImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let captionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var shareButton = UIButton.primaryButton(title: "Share or Print")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = screenTitle
        captionLabel.text = caption
        view.backgroundColor = Constants.Colors.background

        nameLabel.text = venueName
        qrImageView.image = generateQRCode(from: stickerUrl)

        view.addSubview(nameLabel)
        view.addSubview(qrContainer)
        qrContainer.addSubview(qrImageView)
        view.addSubview(captionLabel)
        view.addSubview(shareButton)

        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            nameLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            nameLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),

            qrContainer.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 24),
            qrContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            qrContainer.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.72),
            qrContainer.heightAnchor.constraint(equalTo: qrContainer.widthAnchor),

            qrImageView.topAnchor.constraint(equalTo: qrContainer.topAnchor, constant: 20),
            qrImageView.leadingAnchor.constraint(equalTo: qrContainer.leadingAnchor, constant: 20),
            qrImageView.trailingAnchor.constraint(equalTo: qrContainer.trailingAnchor, constant: -20),
            qrImageView.bottomAnchor.constraint(equalTo: qrContainer.bottomAnchor, constant: -20),

            captionLabel.topAnchor.constraint(equalTo: qrContainer.bottomAnchor, constant: 24),
            captionLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            captionLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),

            shareButton.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 32),
            shareButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            shareButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])
    }

    // MARK: - QR generation

    /// A bitmap-backed QR. A CIImage-backed UIImage shows on screen but draws
    /// as nothing into a renderer, which made shared and printed QRs blank.
    private func generateQRCode(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator"),
              let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        // Scale up so the modules render crisp instead of blurry
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Actions

    @objc private func shareTapped() {
        guard let venueId else { shareImage(); return }
        AlertPresenter.showActionSheet(
            title: nil,
            message: "A sign, a table tent or a counter card prints at real size, with the code 1, 3 or 4 inches wide. The image is for texts and social posts.",
            actions: [
                ("Print a sign or tent…", .default, { [weak self] in self?.showPrintOptions(venueId: venueId) }),
                ("Share image", .default, { [weak self] in self?.shareImage() })
            ],
            from: self,
            sourceView: shareButton
        )
    }

    private func showPrintOptions(venueId: String) {
        let sheet = VenuePrintOptionsViewController(venueId: venueId, venueName: venueName, kind: kind)
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    private func shareImage() {
        guard let image = qrImageView.image,
              let cgRendered = renderShareImage(image) else { return }
        let activityVC = UIActivityViewController(
            activityItems: [cgRendered],
            applicationActivities: nil
        )
        activityVC.popoverPresentationController?.sourceView = shareButton
        present(activityVC, animated: true)
    }

    /// A printable sign: the store name over the QR with a white quiet zone,
    /// so Print and Save Image give something ready to put up
    private func renderShareImage(_ image: UIImage) -> UIImage? {
        let width: CGFloat = 1200
        let height: CGFloat = 1500
        let qrSide: CGFloat = 900
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let centered = NSMutableParagraphStyle()
            centered.alignment = .center
            let name = NSAttributedString(string: venueName, attributes: [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: centered
            ])
            name.draw(with: CGRect(x: 80, y: 90, width: width - 160, height: 180),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)

            context.cgContext.interpolationQuality = .none
            image.draw(in: CGRect(x: (width - qrSide) / 2, y: 300, width: qrSide, height: qrSide))

            let hint = NSAttributedString(string: "Scan with your phone camera", attributes: [
                .font: UIFont.systemFont(ofSize: 44, weight: .semibold),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: centered
            ])
            hint.draw(with: CGRect(x: 80, y: 1260, width: width - 160, height: 70),
                      options: .usesLineFragmentOrigin, context: nil)
        }
    }
}
