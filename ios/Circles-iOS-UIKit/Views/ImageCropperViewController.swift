import UIKit

protocol ImageCropperDelegate: AnyObject {
    func imageCropperDidCrop(_ image: UIImage)
    func imageCropperDidCancel()
}

class ImageCropperViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: ImageCropperDelegate?
    private let originalImage: UIImage
    private var croppedImage: UIImage?
    private var initialSetupComplete = false
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .black
        return scrollView
    }()
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let cropOverlayView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        return view
    }()
    
    private let cropGuideView: UIView = {
        let view = UIView()
        view.layer.borderColor = UIColor.white.cgColor
        view.layer.borderWidth = 2
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }()
    
    private let topToolbar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        return view
    }()
    
    private let cancelButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Cancel", style: .secondary)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .clear
        return button
    }()
    
    private let doneButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Choose", style: .primary)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        button.backgroundColor = .clear
        return button
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Move and Scale"
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Properties
    private var cropSize: CGSize = CGSize(width: 300, height: 300)
    
    // MARK: - Lifecycle
    init(image: UIImage) {
        self.originalImage = image
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCropGuide()
        if initialSetupComplete {
            centerImageInScrollView()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !initialSetupComplete {
            setupImage()
            initialSetupComplete = true
        }
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(imageView)
        view.addSubview(cropOverlayView)
        cropOverlayView.addSubview(cropGuideView)
        view.addSubview(topToolbar)
        topToolbar.addSubview(cancelButton)
        topToolbar.addSubview(titleLabel)
        topToolbar.addSubview(doneButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Top toolbar
            topToolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topToolbar.heightAnchor.constraint(equalToConstant: 60),
            
            // Cancel button
            cancelButton.leadingAnchor.constraint(equalTo: topToolbar.leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
            
            // Title label
            titleLabel.centerXAnchor.constraint(equalTo: topToolbar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
            
            // Done button
            doneButton.trailingAnchor.constraint(equalTo: topToolbar.trailingAnchor, constant: -16),
            doneButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Crop overlay
            cropOverlayView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            cropOverlayView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            cropOverlayView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            cropOverlayView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        ])
        
        // Setup actions
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        
        // Setup scroll view
        scrollView.delegate = self
    }
    
    private func setupImage() {
        imageView.image = originalImage
        imageView.frame = CGRect(origin: .zero, size: originalImage.size)
        
        scrollView.contentSize = originalImage.size
        
        // Calculate zoom scales
        let scaleWidth = scrollView.frame.width / originalImage.size.width
        let scaleHeight = scrollView.frame.height / originalImage.size.height
        let minScale = max(scaleWidth, scaleHeight)
        
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = minScale * 4
        scrollView.zoomScale = minScale * 1.2 // Start slightly zoomed in
    }
    
    private func updateCropGuide() {
        let cropFrame = CGRect(
            x: (view.bounds.width - cropSize.width) / 2,
            y: (scrollView.frame.height - cropSize.height) / 2,
            width: cropSize.width,
            height: cropSize.height
        )
        cropGuideView.frame = cropFrame
        
        // Create dimming mask
        let path = UIBezierPath(rect: cropOverlayView.bounds)
        let cropPath = UIBezierPath(rect: cropFrame)
        path.append(cropPath)
        path.usesEvenOddFillRule = true
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        
        cropOverlayView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        cropOverlayView.layer.addSublayer(maskLayer)
    }
    
    private func centerImageInScrollView() {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        imageView.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX,
                                   y: scrollView.contentSize.height * 0.5 + offsetY)
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        delegate?.imageCropperDidCancel()
        dismiss(animated: true)
    }
    
    @objc private func doneTapped() {
        // Get the visible rect in scroll view coordinates
        let visibleRect = CGRect(
            x: (scrollView.contentOffset.x + (scrollView.bounds.width - cropSize.width) / 2) / scrollView.zoomScale,
            y: (scrollView.contentOffset.y + (scrollView.bounds.height - cropSize.height) / 2) / scrollView.zoomScale,
            width: cropSize.width / scrollView.zoomScale,
            height: cropSize.height / scrollView.zoomScale
        )
        
        // Crop the image
        if let croppedCGImage = originalImage.cgImage?.cropping(to: visibleRect) {
            let croppedImage = UIImage(cgImage: croppedCGImage, scale: originalImage.scale, orientation: originalImage.imageOrientation)
            
            // Resize to final size to ensure reasonable file size
            let finalImage = croppedImage.resized(to: CGSize(width: 800, height: 800))
            
            delegate?.imageCropperDidCrop(finalImage)
            dismiss(animated: true)
        }
    }
}

// MARK: - UIScrollViewDelegate
extension ImageCropperViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageInScrollView()
    }
}