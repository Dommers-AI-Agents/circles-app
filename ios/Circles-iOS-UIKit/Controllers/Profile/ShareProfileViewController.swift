import UIKit
import CoreImage

class ShareProfileViewController: BaseViewController {
    
    // MARK: - Properties
    private let user: User
    private var qrCodeImage: UIImage?
    private let deepLink: String
    
    // MARK: - UI Elements
    private let backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var closeButton: UIButton = {
        let button = UIButton.iconButton(systemName: "xmark")
        button.tintColor = .black
        return button
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 40
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .black
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let qrCodeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.layer.cornerRadius = 12
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.systemGray5.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let buttonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 30
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private lazy var shareButton: UIButton = {
        let button = UIButton.iconButton(systemName: "arrow.up", pointSize: 24)
        button.tintColor = .black
        return button
    }()
    
    private let shareLabel: UILabel = {
        let label = UILabel()
        label.text = "Share profile"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .black
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var copyButton: UIButton = {
        let button = UIButton.iconButton(systemName: "link", pointSize: 24)
        button.tintColor = .black
        return button
    }()
    
    private let copyLabel: UILabel = {
        let label = UILabel()
        label.text = "Copy link"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .black
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var downloadButton: UIButton = {
        let button = UIButton.iconButton(systemName: "arrow.down", pointSize: 24)
        button.tintColor = .black
        return button
    }()
    
    private let downloadLabel: UILabel = {
        let label = UILabel()
        label.text = "Download"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .black
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Circle decoration views
    private var circleDecorations: [UIImageView] = []
    
    // MARK: - Init
    init(user: User) {
        self.user = user
        
        // Extract simple user ID for deep link
        let simpleUserId: String
        if user.id.contains(".") {
            let components = user.id.split(separator: ".")
            simpleUserId = components.count > 1 ? String(components[1]) : user.id
        } else {
            simpleUserId = user.id
        }
        
        self.deepLink = "circles://connect/\(simpleUserId)"
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { false }
    override var enablesPullToRefresh: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        generateQRCode()
        loadUserData()
        addCircleDecorations()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black.withAlphaComponent(0.5)
        
        view.addSubview(backgroundView)
        backgroundView.addSubview(closeButton)
        backgroundView.addSubview(profileImageView)
        backgroundView.addSubview(usernameLabel)
        backgroundView.addSubview(qrCodeImageView)
        
        // Button containers
        let shareContainer = UIView()
        shareContainer.translatesAutoresizingMaskIntoConstraints = false
        shareContainer.addSubview(shareButton)
        shareContainer.addSubview(shareLabel)
        
        let copyContainer = UIView()
        copyContainer.translatesAutoresizingMaskIntoConstraints = false
        copyContainer.addSubview(copyButton)
        copyContainer.addSubview(copyLabel)
        
        let downloadContainer = UIView()
        downloadContainer.translatesAutoresizingMaskIntoConstraints = false
        downloadContainer.addSubview(downloadButton)
        downloadContainer.addSubview(downloadLabel)
        
        buttonsStackView.addArrangedSubview(shareContainer)
        buttonsStackView.addArrangedSubview(copyContainer)
        buttonsStackView.addArrangedSubview(downloadContainer)
        
        backgroundView.addSubview(buttonsStackView)
        
        NSLayoutConstraint.activate([
            // Background view
            backgroundView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            backgroundView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            backgroundView.widthAnchor.constraint(equalToConstant: 320),
            backgroundView.heightAnchor.constraint(equalToConstant: 520),
            
            // Close button
            closeButton.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Profile image
            profileImageView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 60),
            profileImageView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 80),
            profileImageView.heightAnchor.constraint(equalToConstant: 80),
            
            // Username
            usernameLabel.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 12),
            usernameLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 20),
            usernameLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -20),
            
            // QR Code
            qrCodeImageView.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 24),
            qrCodeImageView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            qrCodeImageView.widthAnchor.constraint(equalToConstant: 200),
            qrCodeImageView.heightAnchor.constraint(equalToConstant: 200),
            
            // Buttons stack
            buttonsStackView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -40),
            buttonsStackView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            buttonsStackView.heightAnchor.constraint(equalToConstant: 60),
            
            // Share button container
            shareButton.topAnchor.constraint(equalTo: shareContainer.topAnchor),
            shareButton.centerXAnchor.constraint(equalTo: shareContainer.centerXAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
            
            shareLabel.topAnchor.constraint(equalTo: shareButton.bottomAnchor, constant: 4),
            shareLabel.leadingAnchor.constraint(equalTo: shareContainer.leadingAnchor),
            shareLabel.trailingAnchor.constraint(equalTo: shareContainer.trailingAnchor),
            shareLabel.bottomAnchor.constraint(equalTo: shareContainer.bottomAnchor),
            
            // Copy button container
            copyButton.topAnchor.constraint(equalTo: copyContainer.topAnchor),
            copyButton.centerXAnchor.constraint(equalTo: copyContainer.centerXAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 44),
            copyButton.heightAnchor.constraint(equalToConstant: 44),
            
            copyLabel.topAnchor.constraint(equalTo: copyButton.bottomAnchor, constant: 4),
            copyLabel.leadingAnchor.constraint(equalTo: copyContainer.leadingAnchor),
            copyLabel.trailingAnchor.constraint(equalTo: copyContainer.trailingAnchor),
            copyLabel.bottomAnchor.constraint(equalTo: copyContainer.bottomAnchor),
            
            // Download button container
            downloadButton.topAnchor.constraint(equalTo: downloadContainer.topAnchor),
            downloadButton.centerXAnchor.constraint(equalTo: downloadContainer.centerXAnchor),
            downloadButton.widthAnchor.constraint(equalToConstant: 44),
            downloadButton.heightAnchor.constraint(equalToConstant: 44),
            
            downloadLabel.topAnchor.constraint(equalTo: downloadButton.bottomAnchor, constant: 4),
            downloadLabel.leadingAnchor.constraint(equalTo: downloadContainer.leadingAnchor),
            downloadLabel.trailingAnchor.constraint(equalTo: downloadContainer.trailingAnchor),
            downloadLabel.bottomAnchor.constraint(equalTo: downloadContainer.bottomAnchor),
        ])
        
        // Round corners
        backgroundView.layer.cornerRadius = 20
        backgroundView.clipsToBounds = true
    }
    
    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
        copyButton.addTarget(self, action: #selector(copyButtonTapped), for: .touchUpInside)
        downloadButton.addTarget(self, action: #selector(downloadButtonTapped), for: .touchUpInside)
        
        // Add tap gesture to background to dismiss
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }
    
    private func loadUserData() {
        usernameLabel.text = "@\(user.displayName)"
        
        if let profileImageUrl = user.profilePicture {
            ImageService.shared.loadImage(from: profileImageUrl) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.primary
        }
    }
    
    private func generateQRCode() {
        guard let data = deepLink.data(using: .utf8) else { return }
        
        let context = CIContext()
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return }
        
        // Scale the QR code
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        
        if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
            qrCodeImage = UIImage(cgImage: cgImage)
            
            // Add logo to center of QR code
            if let qrWithLogo = addLogoToQRCode(qrImage: UIImage(cgImage: cgImage)) {
                qrCodeImage = qrWithLogo
                qrCodeImageView.image = qrWithLogo
            } else {
                qrCodeImageView.image = UIImage(cgImage: cgImage)
            }
        }
    }
    
    private func addLogoToQRCode(qrImage: UIImage) -> UIImage? {
        let size = qrImage.size
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        
        qrImage.draw(in: CGRect(origin: .zero, size: size))
        
        // Create a white background circle for the logo
        let logoSize: CGFloat = size.width * 0.25
        let logoRect = CGRect(
            x: (size.width - logoSize) / 2,
            y: (size.height - logoSize) / 2,
            width: logoSize,
            height: logoSize
        )
        
        // Draw white circle background
        UIColor.white.setFill()
        UIBezierPath(ovalIn: logoRect.insetBy(dx: -5, dy: -5)).fill()
        
        // Draw circles logo (simplified version)
        let circleColor = Constants.Colors.primary
        circleColor.setFill()
        
        // Draw three overlapping circles to represent the Circles app logo
        let circleSize = logoSize * 0.3
        let offset = circleSize * 0.3
        
        // Top circle
        let topCircle = UIBezierPath(ovalIn: CGRect(
            x: logoRect.midX - circleSize/2,
            y: logoRect.minY + offset,
            width: circleSize,
            height: circleSize
        ))
        topCircle.fill()
        
        // Bottom left circle
        let leftCircle = UIBezierPath(ovalIn: CGRect(
            x: logoRect.midX - circleSize - offset/2,
            y: logoRect.midY,
            width: circleSize,
            height: circleSize
        ))
        leftCircle.fill()
        
        // Bottom right circle
        let rightCircle = UIBezierPath(ovalIn: CGRect(
            x: logoRect.midX + offset/2,
            y: logoRect.midY,
            width: circleSize,
            height: circleSize
        ))
        rightCircle.fill()
        
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return result
    }
    
    private func addCircleDecorations() {
        // Add decorative circles around the edges
        let positions: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
            // Top row
            (0.15, 0.08, 40), (0.5, 0.05, 50), (0.85, 0.08, 40),
            // Middle sides
            (0.05, 0.25, 45), (0.95, 0.25, 45),
            (0.05, 0.45, 50), (0.95, 0.45, 50),
            // Bottom corners
            (0.1, 0.75, 40), (0.9, 0.75, 40),
            // Bottom row
            (0.2, 0.92, 45), (0.5, 0.95, 50), (0.8, 0.92, 45)
        ]
        
        for position in positions {
            let circleView = UIImageView()
            circleView.translatesAutoresizingMaskIntoConstraints = false
            circleView.contentMode = .scaleAspectFit
            
            // Create a simple circle image
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: position.size, height: position.size))
            let circleImage = renderer.image { ctx in
                Constants.Colors.primary.withAlphaComponent(0.3).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: position.size, height: position.size))
            }
            
            circleView.image = circleImage
            backgroundView.addSubview(circleView)
            backgroundView.sendSubviewToBack(circleView)
            
            NSLayoutConstraint.activate([
                circleView.centerXAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: backgroundView.bounds.width * position.x),
                circleView.centerYAnchor.constraint(equalTo: backgroundView.topAnchor, constant: backgroundView.bounds.height * position.y),
                circleView.widthAnchor.constraint(equalToConstant: position.size),
                circleView.heightAnchor.constraint(equalToConstant: position.size)
            ])
            
            circleDecorations.append(circleView)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update circle decoration positions after layout
        let positions: [(x: CGFloat, y: CGFloat)] = [
            // Top row
            (0.15, 0.08), (0.5, 0.05), (0.85, 0.08),
            // Middle sides
            (0.05, 0.25), (0.95, 0.25),
            (0.05, 0.45), (0.95, 0.45),
            // Bottom corners
            (0.1, 0.75), (0.9, 0.75),
            // Bottom row
            (0.2, 0.92), (0.5, 0.95), (0.8, 0.92)
        ]
        
        for (index, circleView) in circleDecorations.enumerated() {
            if index < positions.count {
                circleView.center = CGPoint(
                    x: backgroundView.bounds.width * positions[index].x,
                    y: backgroundView.bounds.height * positions[index].y
                )
            }
        }
    }
    
    // MARK: - Actions
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        if !backgroundView.frame.contains(location) {
            dismiss(animated: true)
        }
    }
    
    @objc private func shareButtonTapped() {
        guard let qrImage = qrCodeImage else { return }
        
        let shareText = "\(user.displayName) wants to connect with you on Circles!\n\n📱 Scan this QR code or use this link:\n\(deepLink)\n\nDon't have Circles? Download here:\nhttps://apps.apple.com/us/app/favcircles/id6746807095"
        
        let activityViewController = UIActivityViewController(
            activityItems: [shareText, qrImage],
            applicationActivities: nil
        )
        
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = shareButton
            popover.sourceRect = shareButton.bounds
        }
        
        present(activityViewController, animated: true)
    }
    
    @objc private func copyButtonTapped() {
        UIPasteboard.general.string = deepLink
        
        // Show copied feedback
        let label = UILabel()
        label.text = "Link copied!"
        label.backgroundColor = .black.withAlphaComponent(0.8)
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14)
        label.layer.cornerRadius = 20
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            label.widthAnchor.constraint(equalToConstant: 120),
            label.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        UIView.animate(withDuration: 0.3, delay: 1.5, options: .curveEaseOut) {
            label.alpha = 0
        } completion: { _ in
            label.removeFromSuperview()
        }
    }
    
    @objc private func downloadButtonTapped() {
        guard let qrImage = qrCodeImage else { return }
        
        UIImageWriteToSavedPhotosAlbum(qrImage, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        let message = error == nil ? "QR code saved to Photos!" : "Failed to save QR code"
        
        let label = UILabel()
        label.text = message
        label.backgroundColor = .black.withAlphaComponent(0.8)
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14)
        label.layer.cornerRadius = 20
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            label.widthAnchor.constraint(equalToConstant: 200),
            label.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        UIView.animate(withDuration: 0.3, delay: 1.5, options: .curveEaseOut) {
            label.alpha = 0
        } completion: { _ in
            label.removeFromSuperview()
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension ShareProfileViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only handle taps outside the background view
        let location = touch.location(in: view)
        return !backgroundView.frame.contains(location)
    }
}