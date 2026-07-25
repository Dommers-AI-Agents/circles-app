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

    init(venueName: String, stickerUrl: String) {
        self.venueName = venueName
        self.stickerUrl = stickerUrl
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
        label.text = "Customers scan this to save your place and start earning points. Display it in your window or share it anywhere."
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var shareButton = UIButton.primaryButton(title: "Share QR")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scan-to-Save QR"
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
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            qrContainer.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 24),
            qrContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            qrContainer.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.72),
            qrContainer.heightAnchor.constraint(equalTo: qrContainer.widthAnchor),

            qrImageView.topAnchor.constraint(equalTo: qrContainer.topAnchor, constant: 20),
            qrImageView.leadingAnchor.constraint(equalTo: qrContainer.leadingAnchor, constant: 20),
            qrImageView.trailingAnchor.constraint(equalTo: qrContainer.trailingAnchor, constant: -20),
            qrImageView.bottomAnchor.constraint(equalTo: qrContainer.bottomAnchor, constant: -20),

            captionLabel.topAnchor.constraint(equalTo: qrContainer.bottomAnchor, constant: 24),
            captionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            captionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            shareButton.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 32),
            shareButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            shareButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    // MARK: - QR generation

    private func generateQRCode(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator"),
              let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        // Scale up so the modules render crisp instead of blurry
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return UIImage(ciImage: scaled)
    }

    // MARK: - Actions

    @objc private func shareTapped() {
        guard let image = qrImageView.image,
              let cgRendered = renderShareImage(image) else { return }
        let activityVC = UIActivityViewController(
            activityItems: [cgRendered],
            applicationActivities: nil
        )
        activityVC.popoverPresentationController?.sourceView = shareButton
        present(activityVC, animated: true)
    }

    /// CIImage-backed UIImages don't share reliably — render to a bitmap with
    /// a white margin (quiet zone) first
    private func renderShareImage(_ image: UIImage) -> UIImage? {
        let side: CGFloat = 1024
        let inset: CGFloat = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset))
        }
    }
}
