import UIKit

class SplashScreenViewController: BaseViewController {
    
    // MARK: - Properties
    private var progressHandler: ((Double, String) -> Void)?
    private var completionHandler: (() -> Void)?
    
    // MARK: - UI Elements
    private let gradientLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [
            Constants.Colors.primary.cgColor,
            Constants.Colors.primary.withAlphaComponent(0.8).cgColor,
            UIColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1.0).cgColor
        ]
        layer.locations = [0.0, 0.5, 1.0]
        layer.startPoint = CGPoint(x: 0.5, y: 0.0)
        layer.endPoint = CGPoint(x: 0.5, y: 1.0)
        return layer
    }()
    
    private let logoContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let logoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "circle.grid.2x2.fill")
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        imageView.alpha = 0
        return imageView
    }()
    
    private let appNameLabel: UILabel = {
        let label = UILabel()
        label.text = "Circles"
        label.font = UIFont.systemFont(ofSize: 48, weight: .light)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alpha = 0
        return label
    }()
    
    private let taglineLabel: UILabel = {
        let label = UILabel()
        label.text = "Tired of reviews? Trust yourself, create a Circle and add places."
        label.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        label.textColor = .white.withAlphaComponent(0.8)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alpha = 0
        return label
    }()
    
    private let loadingDotsContainer: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alpha = 0
        return stack
    }()
    
    private var loadingDots: [UIView] = []
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alpha = 0
        label.text = "Preparing your experience..."
        return label
    }()
    
    private let progressRing: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
        layer.lineWidth = 3
        layer.lineCap = .round
        layer.strokeEnd = 0
        return layer
    }()
    
    private let progressRingTrack: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.white.withAlphaComponent(0.1).cgColor
        layer.lineWidth = 3
        layer.lineCap = .round
        return layer
    }()
    
    // MARK: - BaseViewController Overrides
    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startAnimations()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
        updateProgressRingPath()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Add gradient background
        view.layer.insertSublayer(gradientLayer, at: 0)
        
        // Add logo container and logo
        view.addSubview(logoContainerView)
        logoContainerView.addSubview(logoImageView)
        
        // Create loading dots
        for _ in 0..<3 {
            let dot = UIView()
            dot.backgroundColor = .white
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            loadingDots.append(dot)
            loadingDotsContainer.addArrangedSubview(dot)
        }
        
        // Add all views
        view.addSubview(appNameLabel)
        view.addSubview(taglineLabel)
        view.addSubview(loadingDotsContainer)
        view.addSubview(statusLabel)
        
        // Add progress ring layers to logo container
        logoContainerView.layer.addSublayer(progressRingTrack)
        logoContainerView.layer.addSublayer(progressRing)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Logo container - centered
            logoContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoContainerView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -80),
            logoContainerView.widthAnchor.constraint(equalToConstant: 140),
            logoContainerView.heightAnchor.constraint(equalToConstant: 140),
            
            // Logo image - inside container
            logoImageView.centerXAnchor.constraint(equalTo: logoContainerView.centerXAnchor),
            logoImageView.centerYAnchor.constraint(equalTo: logoContainerView.centerYAnchor),
            logoImageView.widthAnchor.constraint(equalToConstant: 80),
            logoImageView.heightAnchor.constraint(equalToConstant: 80),
            
            // App name
            appNameLabel.topAnchor.constraint(equalTo: logoContainerView.bottomAnchor, constant: 24),
            appNameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Tagline
            taglineLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 12),
            taglineLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            taglineLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            // Loading dots
            loadingDotsContainer.topAnchor.constraint(equalTo: taglineLabel.bottomAnchor, constant: 30),
            loadingDotsContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Status label
            statusLabel.topAnchor.constraint(equalTo: loadingDotsContainer.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }
    
    private func updateProgressRingPath() {
        let center = CGPoint(x: logoContainerView.bounds.midX, y: logoContainerView.bounds.midY)
        let radius: CGFloat = 65
        let startAngle = -CGFloat.pi / 2
        let endAngle = startAngle + (2 * CGFloat.pi)
        
        let path = UIBezierPath(arcCenter: center,
                               radius: radius,
                               startAngle: startAngle,
                               endAngle: endAngle,
                               clockwise: true)
        
        progressRingTrack.path = path.cgPath
        progressRing.path = path.cgPath
    }
    
    // MARK: - Animations
    private func startAnimations() {
        // Animate logo fade in and scale
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            self.logoImageView.alpha = 1.0
            self.logoImageView.transform = CGAffineTransform.identity
        }
        
        // Animate app name
        UIView.animate(withDuration: 0.3, delay: 0.1, options: .curveEaseOut) {
            self.appNameLabel.alpha = 1.0
        }
        
        // Animate tagline
        UIView.animate(withDuration: 0.3, delay: 0.15, options: .curveEaseOut) {
            self.taglineLabel.alpha = 1.0
        }
        
        // Animate loading dots and status
        UIView.animate(withDuration: 0.3, delay: 0.2, options: .curveEaseOut) {
            self.loadingDotsContainer.alpha = 1.0
            self.statusLabel.alpha = 1.0
        } completion: { _ in
            self.startLoadingDotsAnimation()
        }
        
        // Start progress ring animation immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.animateProgressRing()
        }
    }
    
    private func startLoadingDotsAnimation() {
        for (index, dot) in loadingDots.enumerated() {
            let delay = Double(index) * 0.15
            
            UIView.animateKeyframes(withDuration: 1.5, delay: delay, options: [.repeat, .calculationModeCubic]) {
                UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.3) {
                    dot.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                    dot.alpha = 1.0
                }
                UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.3) {
                    dot.transform = CGAffineTransform.identity
                    dot.alpha = 0.5
                }
            }
        }
    }
    
    private func animateProgressRing() {
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 5.0 // Reduced from 20 seconds
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        
        progressRing.add(animation, forKey: "progressAnimation")
    }
    
    // MARK: - Public Methods
    func updateProgress(_ progress: Double, status: String) {
        print("💫 SplashScreen: updateProgress called - \(progress) - \(status)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { 
                print("❌ SplashScreen: self is nil in updateProgress")
                return 
            }
            
            // Update progress ring
            self.progressRing.strokeEnd = CGFloat(progress)
            
            // Update status text with fade animation
            UIView.transition(with: self.statusLabel,
                            duration: 0.3,
                            options: .transitionCrossDissolve) {
                self.statusLabel.text = status
            }
            
            print("💫 SplashScreen: Progress updated to \(progress)")
        }
    }
    
    func setProgressHandler(_ handler: @escaping (Double, String) -> Void) {
        self.progressHandler = handler
    }
    
    func setCompletionHandler(_ handler: @escaping () -> Void) {
        self.completionHandler = handler
    }
    
    func completeLoading(completion: @escaping () -> Void) {
        print("🎬 SplashScreenViewController: completeLoading called")
        
        // Ensure minimum display time of 0.5 seconds
        let minimumDisplayTime: TimeInterval = 0.5
        let currentTime = CACurrentMediaTime()
        let startTime = view.layer.presentation()?.animationKeys()?.first != nil ? currentTime - 1.0 : currentTime
        let remainingTime = max(0, minimumDisplayTime - (currentTime - startTime))
        
        print("🎬 Remaining time before transition: \(remainingTime)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
            print("🎬 Starting final animations")
            // Final animations
            UIView.animate(withDuration: 0.2, animations: {
                self?.logoImageView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                self?.logoImageView.alpha = 0
                self?.appNameLabel.alpha = 0
                self?.taglineLabel.alpha = 0
                self?.loadingDotsContainer.alpha = 0
                self?.statusLabel.alpha = 0
            }) { _ in
                print("🎬 Final animations complete, calling completion")
                completion()
            }
        }
    }
}