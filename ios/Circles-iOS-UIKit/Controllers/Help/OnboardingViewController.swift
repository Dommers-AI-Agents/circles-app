import UIKit
import AVKit

class OnboardingViewController: UIViewController {

    // MARK: - Properties

    /// When set, the carousel acts as the post-signup welcome flow: on finish
    /// or skip it dismisses and invokes this so the caller can chain the next
    /// onboarding step (instead of marking the whole tutorial complete)
    var onCompletion: (() -> Void)?

    private var currentPage = 0
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to Circles",
            subtitle: "Your personal recommendation platform",
            description: "Share and discover favorite places with your network",
            imageName: "circle.grid.2x2.fill",
            color: Constants.Colors.primary
        ),
        OnboardingPage(
            title: "Create Circles",
            subtitle: "Organize your favorite places",
            description: "Group places by theme like 'Best Coffee Shops' or 'Date Night Spots'",
            imageName: "plus.circle.fill",
            color: .systemBlue
        ),
        OnboardingPage(
            title: "Add Places",
            subtitle: "Build your recommendations",
            description: "Search for places, add from the map, or discover nearby locations",
            imageName: "mappin.circle.fill",
            color: .systemGreen
        ),
        OnboardingPage(
            title: "Connect & Share",
            subtitle: "Build your network",
            description: "Connect with friends to share recommendations and discover new places",
            imageName: "person.2.fill",
            color: .systemPurple
        ),
        OnboardingPage(
            title: "Privacy First",
            subtitle: "You're in control",
            description: "Choose who sees your circles - keep them private, share with connections, or make them public",
            imageName: "lock.fill",
            color: .systemOrange
        )
    ]
    
    // MARK: - UI Elements
    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.delegate = self
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()
    
    private lazy var pageControl: UIPageControl = {
        let control = UIPageControl()
        control.numberOfPages = pages.count
        control.currentPage = 0
        control.pageIndicatorTintColor = Constants.Colors.secondaryLabel.withAlphaComponent(0.3)
        control.currentPageIndicatorTintColor = Constants.Colors.primary
        control.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private lazy var skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Skip", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.tintColor = Constants.Colors.secondaryLabel
        button.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var nextButton: UIButton = {
        let button = UIButton.primaryButton(title: "Next")
        button.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var watchVideoButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Watch Tutorial Video")
        button.addTarget(self, action: #selector(watchVideoTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupPages()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update scroll view content size
        scrollView.contentSize = CGSize(
            width: view.bounds.width * CGFloat(pages.count),
            height: scrollView.bounds.height
        )
        // Update page frames
        for (index, pageView) in scrollView.subviews.enumerated() {
            pageView.frame = CGRect(
                x: view.bounds.width * CGFloat(index),
                y: 0,
                width: view.bounds.width,
                height: scrollView.bounds.height
            )
        }
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        
        // Add subviews
        view.addSubview(scrollView)
        view.addSubview(pageControl)
        view.addSubview(skipButton)
        view.addSubview(nextButton)
        view.addSubview(watchVideoButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Skip button
            skipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: skipButton.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -20),
            
            // Page control
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -32),
            
            // Next button
            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            nextButton.bottomAnchor.constraint(equalTo: watchVideoButton.topAnchor, constant: -16),
            nextButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Watch video button
            watchVideoButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            watchVideoButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            watchVideoButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            watchVideoButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func setupPages() {
        for (index, page) in pages.enumerated() {
            let pageView = createPageView(for: page)
            pageView.frame = CGRect(
                x: view.bounds.width * CGFloat(index),
                y: 0,
                width: view.bounds.width,
                height: scrollView.bounds.height
            )
            scrollView.addSubview(pageView)
        }
    }
    
    private func createPageView(for page: OnboardingPage) -> UIView {
        let container = UIView()
        
        // Icon
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: page.imageName)
        iconImageView.tintColor = page.color
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Title
        let titleLabel = UILabel()
        titleLabel.text = page.title
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Subtitle
        let subtitleLabel = UILabel()
        subtitleLabel.text = page.subtitle
        subtitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        subtitleLabel.textColor = page.color
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Description
        let descriptionLabel = UILabel()
        descriptionLabel.text = page.description
        descriptionLabel.font = .systemFont(ofSize: 16, weight: .regular)
        descriptionLabel.textColor = Constants.Colors.secondaryLabel
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        container.addSubview(iconImageView)
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(descriptionLabel)
        
        // Constraints
        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -120),
            iconImageView.widthAnchor.constraint(equalToConstant: 120),
            iconImageView.heightAnchor.constraint(equalToConstant: 120),
            
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
            
            descriptionLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 48),
            descriptionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -48)
        ])
        
        return container
    }
    
    private func updateUI() {
        // Update button title
        if currentPage == pages.count - 1 {
            nextButton.setTitle("Get Started", for: .normal)
            watchVideoButton.isHidden = false
        } else {
            nextButton.setTitle("Next", for: .normal)
            watchVideoButton.isHidden = true
        }
    }
    
    // MARK: - Actions
    @objc private func skipTapped() {
        completeOnboarding()
    }
    
    @objc private func nextTapped() {
        if currentPage < pages.count - 1 {
            // Go to next page
            currentPage += 1
            let offset = CGPoint(x: view.bounds.width * CGFloat(currentPage), y: 0)
            scrollView.setContentOffset(offset, animated: true)
            pageControl.currentPage = currentPage
            updateUI()
        } else {
            // Complete onboarding
            completeOnboarding()
        }
    }
    
    @objc private func watchVideoTapped() {
        let tutorialVC = TutorialViewController()
        let navController = UINavigationController(rootViewController: tutorialVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc private func pageControlChanged() {
        currentPage = pageControl.currentPage
        let offset = CGPoint(x: view.bounds.width * CGFloat(currentPage), y: 0)
        scrollView.setContentOffset(offset, animated: true)
        updateUI()
    }
    
    private func completeOnboarding() {
        if let onCompletion = onCompletion {
            // Presented as the post-signup welcome flow: dismiss and let the
            // caller chain the next onboarding step (permissions, tutorial)
            dismiss(animated: true) { onCompletion() }
        } else {
            // Standalone use: mark the whole onboarding as completed
            OnboardingManager.shared.completeOnboarding()
            dismiss(animated: true)
        }
    }
}

// MARK: - UIScrollViewDelegate
extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let pageWidth = scrollView.bounds.width
        let currentPage = Int((scrollView.contentOffset.x + pageWidth / 2) / pageWidth)
        
        if currentPage != self.currentPage {
            self.currentPage = currentPage
            pageControl.currentPage = currentPage
            updateUI()
        }
    }
}

// MARK: - OnboardingPage Model
private struct OnboardingPage {
    let title: String
    let subtitle: String
    let description: String
    let imageName: String
    let color: UIColor
}