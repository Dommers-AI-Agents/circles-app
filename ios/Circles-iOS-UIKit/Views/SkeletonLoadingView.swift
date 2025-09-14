import UIKit

// MARK: - Skeleton Loading Views for Progressive Loading
class SkeletonLoadingView: UIView {
    
    private var shimmerLayer: CAGradientLayer?
    private var isAnimating = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSkeleton()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSkeleton()
    }
    
    private func setupSkeleton() {
        backgroundColor = Constants.Colors.tertiaryLabel.withAlphaComponent(0.1)
        layer.cornerRadius = 8
        clipsToBounds = true
    }
    
    func startShimmering() {
        guard !isAnimating else { return }
        isAnimating = true
        
        // Create shimmer gradient
        shimmerLayer = CAGradientLayer()
        shimmerLayer?.colors = [
            UIColor.clear.cgColor,
            Constants.Colors.tertiaryLabel.withAlphaComponent(0.3).cgColor,
            UIColor.clear.cgColor
        ]
        shimmerLayer?.locations = [0.0, 0.5, 1.0]
        shimmerLayer?.startPoint = CGPoint(x: 0.0, y: 0.5)
        shimmerLayer?.endPoint = CGPoint(x: 1.0, y: 0.5)
        shimmerLayer?.frame = bounds
        
        layer.addSublayer(shimmerLayer!)
        
        // Animate shimmer
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1.0, -0.5, 0.0]
        animation.toValue = [1.0, 1.5, 2.0]
        animation.duration = 1.5
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        shimmerLayer?.add(animation, forKey: "shimmer")
    }
    
    func stopShimmering() {
        guard isAnimating else { return }
        isAnimating = false
        
        shimmerLayer?.removeFromSuperlayer()
        shimmerLayer = nil
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        shimmerLayer?.frame = bounds
    }
}

// MARK: - Home Screen Skeleton Components
class HomeScreenSkeletonView: UIView {
    
    private var skeletonViews: [SkeletonLoadingView] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSkeletonLayout()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSkeletonLayout()
    }
    
    private func setupSkeletonLayout() {
        backgroundColor = Constants.Colors.background
        
        // User list skeleton (horizontal)
        let userListContainer = createUserListSkeleton()
        addSubview(userListContainer)
        
        // Activity feed skeleton
        let activityContainer = createActivityFeedSkeleton()
        addSubview(activityContainer)
        
        // Map skeleton
        let mapContainer = createMapSkeleton()
        addSubview(mapContainer)
        
        // Layout constraints
        userListContainer.translatesAutoresizingMaskIntoConstraints = false
        activityContainer.translatesAutoresizingMaskIntoConstraints = false
        mapContainer.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // User list at top
            userListContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            userListContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            userListContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            userListContainer.heightAnchor.constraint(equalToConstant: 80),
            
            // Map skeleton
            mapContainer.topAnchor.constraint(equalTo: userListContainer.bottomAnchor, constant: 16),
            mapContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            mapContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            mapContainer.heightAnchor.constraint(equalToConstant: 200),
            
            // Activity feed
            activityContainer.topAnchor.constraint(equalTo: mapContainer.bottomAnchor, constant: 16),
            activityContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            activityContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            activityContainer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16)
        ])
    }
    
    private func createUserListSkeleton() -> UIView {
        let container = UIView()
        
        // Title skeleton
        let titleSkeleton = SkeletonLoadingView()
        titleSkeleton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleSkeleton)
        skeletonViews.append(titleSkeleton)
        
        // User avatars skeleton
        let scrollContainer = UIView()
        scrollContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollContainer)
        
        var previousAvatar: UIView = scrollContainer
        
        for i in 0..<6 {
            let avatar = SkeletonLoadingView()
            avatar.translatesAutoresizingMaskIntoConstraints = false
            avatar.layer.cornerRadius = 25 // Circular
            scrollContainer.addSubview(avatar)
            skeletonViews.append(avatar)
            
            NSLayoutConstraint.activate([
                avatar.widthAnchor.constraint(equalToConstant: 50),
                avatar.heightAnchor.constraint(equalToConstant: 50),
                avatar.centerYAnchor.constraint(equalTo: scrollContainer.centerYAnchor),
                avatar.leadingAnchor.constraint(equalTo: i == 0 ? scrollContainer.leadingAnchor : previousAvatar.trailingAnchor, constant: i == 0 ? 0 : 12)
            ])
            
            previousAvatar = avatar
        }
        
        NSLayoutConstraint.activate([
            titleSkeleton.topAnchor.constraint(equalTo: container.topAnchor),
            titleSkeleton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleSkeleton.widthAnchor.constraint(equalToConstant: 120),
            titleSkeleton.heightAnchor.constraint(equalToConstant: 16),
            
            scrollContainer.topAnchor.constraint(equalTo: titleSkeleton.bottomAnchor, constant: 8),
            scrollContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollContainer.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        return container
    }
    
    private func createMapSkeleton() -> SkeletonLoadingView {
        let mapSkeleton = SkeletonLoadingView()
        skeletonViews.append(mapSkeleton)
        return mapSkeleton
    }
    
    private func createActivityFeedSkeleton() -> UIView {
        let container = UIView()
        
        // Title skeleton
        let titleSkeleton = SkeletonLoadingView()
        titleSkeleton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleSkeleton)
        skeletonViews.append(titleSkeleton)
        
        // Activity items
        var previousItem: UIView = titleSkeleton
        
        for i in 0..<4 {
            let activityItem = createActivityItemSkeleton()
            activityItem.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(activityItem)
            
            NSLayoutConstraint.activate([
                activityItem.topAnchor.constraint(equalTo: previousItem.bottomAnchor, constant: i == 0 ? 16 : 12),
                activityItem.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                activityItem.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                activityItem.heightAnchor.constraint(equalToConstant: 60)
            ])
            
            previousItem = activityItem
        }
        
        NSLayoutConstraint.activate([
            titleSkeleton.topAnchor.constraint(equalTo: container.topAnchor),
            titleSkeleton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleSkeleton.widthAnchor.constraint(equalToConstant: 140),
            titleSkeleton.heightAnchor.constraint(equalToConstant: 16),
            
            previousItem.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    private func createActivityItemSkeleton() -> UIView {
        let container = UIView()
        
        // Avatar
        let avatar = SkeletonLoadingView()
        avatar.layer.cornerRadius = 20
        avatar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(avatar)
        skeletonViews.append(avatar)
        
        // Text lines
        let line1 = SkeletonLoadingView()
        line1.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line1)
        skeletonViews.append(line1)
        
        let line2 = SkeletonLoadingView()
        line2.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line2)
        skeletonViews.append(line2)
        
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            avatar.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),
            
            line1.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            line1.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            line1.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            line1.heightAnchor.constraint(equalToConstant: 14),
            
            line2.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            line2.topAnchor.constraint(equalTo: line1.bottomAnchor, constant: 6),
            line2.widthAnchor.constraint(equalTo: line1.widthAnchor, multiplier: 0.7),
            line2.heightAnchor.constraint(equalToConstant: 12)
        ])
        
        return container
    }
    
    func startAnimating() {
        for skeletonView in skeletonViews {
            skeletonView.startShimmering()
        }
    }
    
    func stopAnimating() {
        for skeletonView in skeletonViews {
            skeletonView.stopShimmering()
        }
    }
}

// MARK: - Usage Helper
extension UIViewController {
    func showSkeletonLoading(in containerView: UIView) -> HomeScreenSkeletonView {
        let skeletonView = HomeScreenSkeletonView()
        skeletonView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(skeletonView)
        
        NSLayoutConstraint.activate([
            skeletonView.topAnchor.constraint(equalTo: containerView.topAnchor),
            skeletonView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            skeletonView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        skeletonView.startAnimating()
        return skeletonView
    }
    
    func hideSkeletonLoading(_ skeletonView: HomeScreenSkeletonView) {
        UIView.animate(withDuration: 0.3, animations: {
            skeletonView.alpha = 0
        }) { _ in
            skeletonView.stopAnimating()
            skeletonView.removeFromSuperview()
        }
    }
}