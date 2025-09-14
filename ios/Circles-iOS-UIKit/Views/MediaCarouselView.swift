import UIKit
import AVKit

protocol MediaCarouselViewDelegate: AnyObject {
    func mediaCarouselView(_ carouselView: MediaCarouselView, didTapVideoAt index: Int, url: String)
}

class MediaCarouselView: UIView {
    
    // MARK: - Properties
    
    weak var delegate: MediaCarouselViewDelegate?
    
    private var mediaItems: [MediaItem] = []
    private var currentIndex = 0
    
    // MARK: - UI Elements
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let pageControl: UIPageControl = {
        let control = UIPageControl()
        control.currentPageIndicatorTintColor = .white
        control.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.5)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let previousButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.left.circle.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    private let nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.right.circle.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    private let contentStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        backgroundColor = Constants.Colors.lightGray
        
        // Add subviews
        addSubview(scrollView)
        scrollView.addSubview(contentStackView)
        addSubview(pageControl)
        addSubview(previousButton)
        addSubview(nextButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Content stack view
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            
            // Page control
            pageControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            pageControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageControl.heightAnchor.constraint(equalToConstant: 20),
            
            // Previous button
            previousButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 40),
            previousButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Next button
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 40),
            nextButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Setup actions
        scrollView.delegate = self
        previousButton.addTarget(self, action: #selector(previousButtonTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
        
        // Add hover gesture for showing/hiding navigation buttons
        let hoverGesture = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hoverGesture)
        
        // Add tap gesture to show/hide controls
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Public Methods
    
    func configure(with mediaItems: [MediaItem]) {
        print("📸 MediaCarouselView: configure() called with \(mediaItems.count) items")
        for (index, item) in mediaItems.enumerated() {
            switch item {
            case .photo(let url):
                print("  Item \(index + 1): Photo URL - \(url ?? "nil")")
            case .photoImage(_):
                print("  Item \(index + 1): Photo UIImage")
            case .video(let thumbnailUrl, let videoUrl):
                print("  Item \(index + 1): Video - thumb: \(thumbnailUrl ?? "nil"), video: \(videoUrl ?? "nil")")
            case .attributedPhoto(let url, let uploadedBy, let source):
                print("  Item \(index + 1): Attributed Photo - URL: \(url), by: \(uploadedBy), source: \(source)")
            }
        }
        
        self.mediaItems = mediaItems
        currentIndex = 0
        
        // Clear existing views
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Add media views
        var mediaViews: [UIView] = []
        for (index, item) in mediaItems.enumerated() {
            let mediaView = createMediaView(for: item, at: index)
            contentStackView.addArrangedSubview(mediaView)
            mediaViews.append(mediaView)
        }
        
        // Now that views are in the hierarchy, add width constraints
        for mediaView in mediaViews {
            NSLayoutConstraint.activate([
                mediaView.widthAnchor.constraint(equalTo: widthAnchor)
            ])
        }
        
        // Update page control
        pageControl.numberOfPages = mediaItems.count
        pageControl.currentPage = 0
        pageControl.isHidden = mediaItems.count <= 1
        print("📸 MediaCarouselView: Page control - pages: \(pageControl.numberOfPages), hidden: \(pageControl.isHidden)")
        
        // Update navigation buttons
        updateNavigationButtons()
        print("📸 MediaCarouselView: Configuration complete - \(contentStackView.arrangedSubviews.count) views in stack")
    }
    
    // MARK: - Private Methods
    
    private func createMediaView(for item: MediaItem, at index: Int) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        switch item {
        case .photo(let url):
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = Constants.Colors.lightGray
            imageView.translatesAutoresizingMaskIntoConstraints = false
            
            // Load image
            if let imageUrl = url {
                ImageService.shared.loadImage(from: imageUrl) { image in
                    DispatchQueue.main.async {
                        imageView.image = image
                    }
                }
            }
            
            containerView.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            
        case .photoImage(let image):
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = Constants.Colors.lightGray
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.image = image
            
            containerView.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            
        case .video(let thumbnailUrl, let videoUrl):
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = Constants.Colors.lightGray
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.isUserInteractionEnabled = true
            
            // Load thumbnail
            if let thumbnailUrl = thumbnailUrl {
                ImageService.shared.loadImage(from: thumbnailUrl) { image in
                    DispatchQueue.main.async {
                        imageView.image = image
                    }
                }
            }
            
            // Add play button overlay
            let playButton = UIButton(type: .system)
            playButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
            playButton.tintColor = .white
            playButton.translatesAutoresizingMaskIntoConstraints = false
            playButton.tag = index
            playButton.addTarget(self, action: #selector(playButtonTapped(_:)), for: .touchUpInside)
            
            containerView.addSubview(imageView)
            containerView.addSubview(playButton)
            
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                
                playButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                playButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                playButton.widthAnchor.constraint(equalToConstant: 80),
                playButton.heightAnchor.constraint(equalToConstant: 80)
            ])
            
        case .attributedPhoto(let url, let uploadedBy, let source):
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = Constants.Colors.lightGray
            imageView.translatesAutoresizingMaskIntoConstraints = false
            
            // Load image
            ImageService.shared.loadImage(from: url) { image in
                DispatchQueue.main.async {
                    imageView.image = image
                }
            }
            
            // Create attribution label
            let attributionLabel = UILabel()
            attributionLabel.text = "Photo by \(uploadedBy)"
            attributionLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
            attributionLabel.textColor = .white
            attributionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            attributionLabel.layer.cornerRadius = 4
            attributionLabel.clipsToBounds = true
            attributionLabel.textAlignment = .center
            attributionLabel.translatesAutoresizingMaskIntoConstraints = false
            
            // Add padding to the label
            let paddingView = UIView()
            paddingView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            paddingView.layer.cornerRadius = 4
            paddingView.clipsToBounds = true
            paddingView.translatesAutoresizingMaskIntoConstraints = false
            
            paddingView.addSubview(attributionLabel)
            
            containerView.addSubview(imageView)
            containerView.addSubview(paddingView)
            
            NSLayoutConstraint.activate([
                // Image constraints
                imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                
                // Attribution label constraints
                paddingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
                paddingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
                
                attributionLabel.topAnchor.constraint(equalTo: paddingView.topAnchor, constant: 4),
                attributionLabel.leadingAnchor.constraint(equalTo: paddingView.leadingAnchor, constant: 8),
                attributionLabel.trailingAnchor.constraint(equalTo: paddingView.trailingAnchor, constant: -8),
                attributionLabel.bottomAnchor.constraint(equalTo: paddingView.bottomAnchor, constant: -4)
            ])
        }
        
        return containerView
    }
    
    private func updateNavigationButtons() {
        let showButtons = mediaItems.count > 1
        previousButton.isHidden = !showButtons || currentIndex == 0
        nextButton.isHidden = !showButtons || currentIndex == mediaItems.count - 1
    }
    
    // MARK: - Actions
    
    @objc private func previousButtonTapped() {
        guard currentIndex > 0 else { return }
        scrollToPage(currentIndex - 1)
    }
    
    @objc private func nextButtonTapped() {
        guard currentIndex < mediaItems.count - 1 else { return }
        scrollToPage(currentIndex + 1)
    }
    
    @objc private func pageControlChanged() {
        scrollToPage(pageControl.currentPage)
    }
    
    @objc private func playButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < mediaItems.count,
              case .video(_, let videoUrl) = mediaItems[index],
              let videoUrl = videoUrl else { return }
        
        delegate?.mediaCarouselView(self, didTapVideoAt: index, url: videoUrl)
    }
    
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard mediaItems.count > 1 else { return }
        
        switch gesture.state {
        case .began, .changed:
            showNavigationButtons()
        case .ended:
            hideNavigationButtons()
        default:
            break
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard mediaItems.count > 1 else { return }
        
        if previousButton.alpha == 0 {
            showNavigationButtons()
            hideNavigationButtonsAfterDelay()
        }
    }
    
    private func showNavigationButtons() {
        UIView.animate(withDuration: 0.2) {
            self.previousButton.alpha = self.currentIndex > 0 ? 1 : 0
            self.nextButton.alpha = self.currentIndex < self.mediaItems.count - 1 ? 1 : 0
        }
    }
    
    private func hideNavigationButtons() {
        UIView.animate(withDuration: 0.2) {
            self.previousButton.alpha = 0
            self.nextButton.alpha = 0
        }
    }
    
    private func hideNavigationButtonsAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.hideNavigationButtons()
        }
    }
    
    private func scrollToPage(_ page: Int) {
        let xOffset = CGFloat(page) * bounds.width
        scrollView.setContentOffset(CGPoint(x: xOffset, y: 0), animated: true)
    }
}

// MARK: - UIScrollViewDelegate

extension MediaCarouselView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        
        let page = Int(round(scrollView.contentOffset.x / pageWidth))
        if page != currentIndex && page >= 0 && page < mediaItems.count {
            currentIndex = page
            pageControl.currentPage = page
            updateNavigationButtons()
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MediaCarouselView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Ensure touch.view is valid and is a UIView
        guard let touchView = touch.view as? UIView else {
            return false
        }
        
        // Don't handle tap on buttons
        if touchView is UIButton {
            return false
        }
        return true
    }
}

// MARK: - MediaItem

enum MediaItem {
    case photo(url: String?)
    case photoImage(image: UIImage)
    case video(thumbnailUrl: String?, videoUrl: String?)
    case attributedPhoto(url: String, uploadedBy: String, source: MediaSource)
}