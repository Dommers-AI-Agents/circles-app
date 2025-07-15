import UIKit

class FullScreenImageViewController: BaseViewController {
    
    // MARK: - Properties
    private var imageURL: String?
    private var image: UIImage?
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .fast
        return scrollView
    }()
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        return imageView
    }()
    
    private lazy var closeButton: UIButton = {
        let button = UIButton.iconButton(systemName: "xmark.circle.fill", pointSize: 24)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.color = .white
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Initialization
    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }
    
    init(imageURL: String) {
        self.imageURL = imageURL
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - BaseViewController Overrides
    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        loadImage()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hide status bar for full-screen experience
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore status bar
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(imageView)
        view.addSubview(closeButton)
        view.addSubview(loadingIndicator)
        
        // Configure scroll view
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.0
        scrollView.zoomScale = 1.0
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Close button
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
    }
    
    private func setupGestures() {
        // Single tap to dismiss
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        view.addGestureRecognizer(singleTap)
        
        // Double tap to zoom
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        
        // Prevent single tap from firing when double tapping
        singleTap.require(toFail: doubleTap)
        
        // Pan gesture for dismiss on swipe down
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        view.addGestureRecognizer(panGesture)
    }
    
    private func loadImage() {
        if let image = self.image {
            // Use provided image
            displayImage(image)
        } else if let imageURL = self.imageURL {
            // Load image from URL
            loadingIndicator.startAnimating()
            
            ImageService.shared.loadImage(from: imageURL) { [weak self] image in
                DispatchQueue.main.async {
                    self?.loadingIndicator.stopAnimating()
                    
                    if let image = image {
                        self?.displayImage(image)
                    } else {
                        // Show placeholder or error state
                        self?.displayImage(UIImage(systemName: "person.circle.fill") ?? UIImage())
                    }
                }
            }
        }
    }
    
    private func displayImage(_ image: UIImage) {
        imageView.image = image
        updateImageViewConstraints()
    }
    
    private func updateImageViewConstraints() {
        guard let image = imageView.image else { return }
        
        let imageSize = image.size
        let scrollViewSize = scrollView.bounds.size
        
        // Calculate the scale to fit the image in the scroll view
        let widthScale = scrollViewSize.width / imageSize.width
        let heightScale = scrollViewSize.height / imageSize.height
        let minScale = min(widthScale, heightScale)
        
        // Update image view size
        let scaledWidth = imageSize.width * minScale
        let scaledHeight = imageSize.height * minScale
        
        imageView.frame = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
        scrollView.contentSize = imageView.frame.size
        
        // Center the image initially
        centerImage()
        
        // Update zoom scales
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = max(minScale * 3, 1.0)
        scrollView.zoomScale = minScale
    }
    
    private func centerImage() {
        let scrollViewSize = scrollView.bounds.size
        let imageViewSize = imageView.frame.size
        
        let horizontalSpace = max(0, (scrollViewSize.width - imageViewSize.width) / 2)
        let verticalSpace = max(0, (scrollViewSize.height - imageViewSize.height) / 2)
        
        scrollView.contentInset = UIEdgeInsets(
            top: verticalSpace,
            left: horizontalSpace,
            bottom: verticalSpace,
            right: horizontalSpace
        )
    }
    
    // MARK: - Actions
    @objc private func closeButtonTapped() {
        dismiss()
    }
    
    @objc private func handleSingleTap() {
        dismiss()
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            // Zoom out
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            // Zoom in to the tapped point
            let tapPoint = gesture.location(in: imageView)
            let zoomScale = scrollView.maximumZoomScale
            let zoomRect = CGRect(
                x: tapPoint.x - (scrollView.bounds.width / zoomScale) / 2,
                y: tapPoint.y - (scrollView.bounds.height / zoomScale) / 2,
                width: scrollView.bounds.width / zoomScale,
                height: scrollView.bounds.height / zoomScale
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        
        switch gesture.state {
        case .changed:
            // Only allow downward swipe to dismiss when not zoomed
            if scrollView.zoomScale <= scrollView.minimumZoomScale && translation.y > 0 {
                let progress = min(translation.y / 200, 1.0)
                let alpha = 1.0 - progress
                view.backgroundColor = UIColor.black.withAlphaComponent(alpha)
                
                // Apply transform
                let scale = 1.0 - (progress * 0.3)
                let transform = CGAffineTransform(scaleX: scale, y: scale)
                    .concatenating(CGAffineTransform(translationX: 0, y: translation.y))
                scrollView.transform = transform
            }
            
        case .ended:
            // Dismiss if swiped down enough or with enough velocity
            if translation.y > 100 || velocity.y > 500 {
                dismiss()
            } else {
                // Reset to original state
                UIView.animate(withDuration: 0.3) {
                    self.view.backgroundColor = .black
                    self.scrollView.transform = .identity
                }
            }
            
        default:
            break
        }
    }
    
    private func dismiss() {
        UIView.animate(withDuration: 0.3, animations: {
            self.view.alpha = 0
        }) { _ in
            self.dismiss(animated: false)
        }
    }
    
    // MARK: - Layout
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if imageView.image != nil {
            updateImageViewConstraints()
        }
    }
}

// MARK: - UIScrollViewDelegate
extension FullScreenImageViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }
}