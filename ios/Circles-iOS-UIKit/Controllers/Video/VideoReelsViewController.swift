import UIKit
import AVFoundation
import AVKit

class VideoReelsViewController: UIViewController {
    
    // MARK: - Properties
    private var reels: [PlaceVideo]
    private var currentIndex: Int
    private var players: [Int: AVPlayer] = [:]
    private var playerLayers: [Int: AVPlayerLayer] = [:]
    
    // Navigation handler for place
    var placeNavigationHandler: ((String) -> Void)?
    
    // MARK: - UI Elements
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .black
        cv.isPagingEnabled = true
        cv.showsVerticalScrollIndicator = false
        cv.contentInsetAdjustmentBehavior = .never
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Initialization
    init(reels: [PlaceVideo], startIndex: Int = 0) {
        self.reels = reels
        self.currentIndex = startIndex
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCollectionView()
        preloadVideos()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hide status bar for full-screen experience
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Scroll to start index
        if currentIndex > 0 {
            let indexPath = IndexPath(item: currentIndex, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        }
        // Preload current and adjacent videos
        preloadVideos()
        // Start playing immediately
        playCurrentVideo()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pauseAllVideos()
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        view.addSubview(collectionView)
        view.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    }
    
    private func setupCollectionView() {
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(VideoReelCell.self, forCellWithReuseIdentifier: "VideoReelCell")
    }
    
    // MARK: - Video Management
    private func preloadVideos() {
        // Preload videos around current index
        let preloadRange = max(0, currentIndex - 1)...min(reels.count - 1, currentIndex + 1)
        
        for index in preloadRange {
            if players[index] == nil {
                loadVideo(at: index)
            }
        }
    }
    
    private func loadVideo(at index: Int) {
        guard index >= 0 && index < reels.count else { return }
        
        let reel = reels[index]
        
        // Skip loading video player for photos
        if reel.contentType == "photo" {
            // Photos don't need video players
            return
        }
        
        guard let urlString = reel.videoUrl ?? reel.previewUrl,
              let url = URL(string: urlString) else { 
            print("❌ VideoReels: Invalid video URL for reel \(reel.id)")
            return 
        }
        
        // Create player item to observe status
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.actionAtItemEnd = .none // Loop video
        
        // Observe player item status
        playerItem.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        
        // Add observer for looping
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Enable audio playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ VideoReels: Failed to setup audio session: \(error)")
        }
        
        players[index] = player
        print("✅ VideoReels: Loaded video for index \(index)")
    }
    
    private func playCurrentVideo() {
        // Pause all videos first
        pauseAllVideos()
        
        // Check if current item is a photo
        if currentIndex < reels.count && reels[currentIndex].contentType == "photo" {
            // Photos don't need to be played, just track the view
            trackVideoView(at: currentIndex)
            return
        }
        
        // Play current video
        if let player = players[currentIndex] {
            // Check if player is ready
            if player.currentItem?.status == .readyToPlay {
                player.play()
                print("✅ VideoReels: Playing video at index \(currentIndex)")
            } else {
                print("⏳ VideoReels: Player not ready at index \(currentIndex), waiting...")
                // Will play when ready via KVO observer
            }
        } else {
            print("📥 VideoReels: Loading video at index \(currentIndex)")
            loadVideo(at: currentIndex)
        }
        
        // Track view
        trackVideoView(at: currentIndex)
    }
    
    private func pauseAllVideos() {
        for player in players.values {
            player.pause()
        }
    }
    
    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        guard let playerItem = notification.object as? AVPlayerItem else { return }
        playerItem.seek(to: .zero, completionHandler: nil)
    }
    
    private func trackVideoView(at index: Int) {
        guard index >= 0 && index < reels.count else { return }
        
        let reel = reels[index]
        let endpoint = "videos/reels/\(reel.id)/view"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: [:],
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            // Silent tracking, no need to handle response
            if case .failure(let error) = result {
                print("❌ VideoReels: Failed to track view: \(error)")
            }
        }
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - Memory Management
    private func releaseDistantVideos() {
        // Release videos that are more than 2 positions away
        for (index, player) in players {
            if abs(index - currentIndex) > 2 {
                player.pause()
                players.removeValue(forKey: index)
                playerLayers.removeValue(forKey: index)
            }
        }
    }
    
    // MARK: - KVO
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let playerItem = object as? AVPlayerItem {
            switch playerItem.status {
            case .readyToPlay:
                // Find which player this item belongs to and play if it's current
                for (index, player) in players where player.currentItem == playerItem {
                    if index == currentIndex {
                        player.play()
                        print("✅ VideoReels: Auto-playing video at index \(index) after ready")
                    }
                    break
                }
            case .failed:
                print("❌ VideoReels: Player item failed: \(playerItem.error?.localizedDescription ?? "Unknown error")")
            default:
                break
            }
        }
    }
    
    deinit {
        // Remove all observers
        for player in players.values {
            player.currentItem?.removeObserver(self, forKeyPath: "status")
        }
        NotificationCenter.default.removeObserver(self)
        pauseAllVideos()
    }
}

// MARK: - UICollectionViewDataSource
extension VideoReelsViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return reels.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VideoReelCell", for: indexPath) as! VideoReelCell
        
        let reel = reels[indexPath.item]
        
        // Get or create player for this index (only for videos)
        if reel.contentType != "photo" && players[indexPath.item] == nil {
            loadVideo(at: indexPath.item)
        }
        
        // Pass player only if it's a video
        let player = reel.contentType == "photo" ? nil : players[indexPath.item]
        cell.configure(with: reel, player: player)
        
        cell.delegate = self
        
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension VideoReelsViewController: UICollectionViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentIndex()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateCurrentIndex()
        }
    }
    
    private func updateCurrentIndex() {
        let center = CGPoint(x: collectionView.frame.size.width / 2 + collectionView.contentOffset.x,
                            y: collectionView.frame.size.height / 2 + collectionView.contentOffset.y)
        
        if let indexPath = collectionView.indexPathForItem(at: center), indexPath.item != currentIndex {
            currentIndex = indexPath.item
            playCurrentVideo()
            preloadVideos()
            releaseDistantVideos()
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout
extension VideoReelsViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.frame.size
    }
}

// MARK: - VideoReelCellDelegate
extension VideoReelsViewController: VideoReelCellDelegate {
    func videoReelCellDidTapLike(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        var reel = reels[indexPath.item]
        
        // Toggle like state optimistically
        let wasLiked = reel.likedByCurrentUser ?? false
        reel.likedByCurrentUser = !wasLiked
        reel.likeCount = wasLiked ? max(0, reel.likeCount - 1) : reel.likeCount + 1
        reels[indexPath.item] = reel
        
        // Update cell
        cell.configure(with: reel, player: players[indexPath.item])
        
        // Call API
        let endpoint = wasLiked 
            ? "videos/reels/\(reel.id)/like"
            : "videos/reels/\(reel.id)/like"
        let method: RequestMethod = wasLiked ? .delete : .post
        
        APIService.shared.request(
            endpoint: endpoint,
            method: method,
            requiresAuth: true
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            if case .failure(let error) = result {
                // Revert on failure
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    reel.likedByCurrentUser = wasLiked
                    reel.likeCount = wasLiked ? reel.likeCount + 1 : max(0, reel.likeCount - 1)
                    self.reels[indexPath.item] = reel
                    
                    if let cell = self.collectionView.cellForItem(at: indexPath) as? VideoReelCell {
                        cell.configure(with: reel, player: self.players[indexPath.item])
                    }
                    
                    print("Failed to update like: \(error)")
                }
            }
        }
    }
    
    func videoReelCellDidTapComment(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Pause current video
        pauseAllVideos()
        
        // Present video engagement view controller (likes and comments)
        let engagementVC = VideoEngagementViewController(video: reel)
        let nav = UINavigationController(rootViewController: engagementVC)
        nav.modalPresentationStyle = .pageSheet
        
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            // Start with comments tab selected
            engagementVC.setSelectedSegment(1)
        }
        
        present(nav, animated: true) { [weak self] in
            // Resume video after presenting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.playCurrentVideo()
            }
        }
    }
    
    func videoReelCellDidTapShare(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Share video
        let shareText = "Check out this place: \(reel.placeName)"
        let shareItems: [Any] = [shareText]
        
        let activityVC = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
        
        // For iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        
        present(activityVC, animated: true)
    }
    
    func videoReelCellDidTapProfile(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let user = reels[indexPath.item].user else { return }
        
        // Dismiss and show profile
        dismiss(animated: true) { [weak self] in
            // Get the presenting view controller (should be the tab bar controller)
            guard let window = UIApplication.shared.windows.first,
                  let rootVC = window.rootViewController as? UITabBarController,
                  let navController = rootVC.selectedViewController as? UINavigationController else {
                print("❌ VideoReelsViewController: Unable to find navigation controller")
                return
            }
            
            // Create and push profile view controller
            let profileVC = ProfileViewController()
            profileVC.configureWith(user: user)
            navController.pushViewController(profileVC, animated: true)
            
            print("✅ VideoReelsViewController: Navigating to profile for user: \(user.displayName)")
        }
    }
    
    func videoReelCellDidTapPlace(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Dismiss and navigate to place
        dismiss(animated: true) { [weak self] in
            // First try the navigation handler if set
            if let handler = self?.placeNavigationHandler {
                handler(reel.placeId)
            } else {
                // Otherwise navigate directly - fetch the place details first
                guard let window = UIApplication.shared.windows.first,
                      let rootVC = window.rootViewController as? UITabBarController,
                      let navController = rootVC.selectedViewController as? UINavigationController else {
                    print("❌ VideoReelsViewController: Unable to find navigation controller for place")
                    return
                }
                
                // Show loading indicator
                let loadingAlert = UIAlertController(title: nil, message: "Loading place details...", preferredStyle: .alert)
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.translatesAutoresizingMaskIntoConstraints = false
                spinner.startAnimating()
                loadingAlert.view.addSubview(spinner)
                NSLayoutConstraint.activate([
                    spinner.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
                    spinner.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -20)
                ])
                
                if let presentingVC = window.rootViewController?.presentedViewController {
                    presentingVC.present(loadingAlert, animated: true)
                } else {
                    window.rootViewController?.present(loadingAlert, animated: true)
                }
                
                // Fetch place details from API
                APIService.shared.request(
                    endpoint: "places/\(reel.placeId)",
                    method: .get
                ) { (result: Result<PlaceResponse, APIError>) in
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true) {
                            switch result {
                            case .success(let response):
                                if response.success {
                                    // Create and push place detail view controller
                                    let placeDetailVC = PlaceDetailViewController(place: response.place, circle: nil)
                                    navController.pushViewController(placeDetailVC, animated: true)
                                    print("✅ VideoReelsViewController: Navigating to place: \(reel.placeName)")
                                }
                            case .failure(let error):
                                print("❌ VideoReelsViewController: Failed to fetch place details: \(error)")
                                // Show error alert
                                let errorAlert = UIAlertController(
                                    title: "Error",
                                    message: "Unable to load place details",
                                    preferredStyle: .alert
                                )
                                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                                window.rootViewController?.present(errorAlert, animated: true)
                            }
                        }
                    }
                }
                
                print("📍 VideoReelsViewController: Fetching place details for: \(reel.placeName)")
            }
        }
    }
    
    func videoReelCellDidTapReaction(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Check if video has an activity
        guard let activityId = reel.activityId else {
            print("No activity found for this video")
            return
        }
        
        // Show reaction picker
        let reactionPicker = ReactionPickerView()
        reactionPicker.delegate = self
        if let userReaction = reel.userActivityReaction {
            // Convert emoji string to ReactionStyle if possible
            ReactionStyle.allCases.forEach { style in
                if style.rawValue == userReaction {
                    // Would need to add a method to set selected reaction
                }
            }
        }
        
        view.addSubview(reactionPicker)
        reactionPicker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            reactionPicker.topAnchor.constraint(equalTo: view.topAnchor),
            reactionPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reactionPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            reactionPicker.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        reactionPicker.show(from: cell)
    }
    
    func videoReelCellDidTapActivityEngagement(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Check if video has an activity
        guard let activityId = reel.activityId else {
            print("No activity found for this video")
            return
        }
        
        // Pause video
        pauseAllVideos()
        
        // Fetch and show activity engagement
        fetchActivityAndShowEngagement(videoId: reel.id)
    }
    
    func videoReelCellDidTapLikeCount(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Pause current video
        pauseAllVideos()
        
        // Present video engagement view controller (likes tab)
        let engagementVC = VideoEngagementViewController(video: reel)
        let nav = UINavigationController(rootViewController: engagementVC)
        nav.modalPresentationStyle = .pageSheet
        
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            // Start with likes tab selected
            engagementVC.setSelectedSegment(0)
        }
        
        present(nav, animated: true) { [weak self] in
            // Resume video after presenting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.playCurrentVideo()
            }
        }
    }
    
    private func fetchActivityAndShowEngagement(videoId: String) {
        let endpoint = "videos/\(videoId)/activity"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get
        ) { [weak self] (result: Result<SingleActivityResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.presentActivityEngagement(response.data)
                case .failure(let error):
                    print("Failed to fetch activity: \(error)")
                }
            }
        }
    }
    
    private func presentActivityEngagement(_ activity: Activity) {
        let engagementVC = ActivityEngagementViewController(activity: activity)
        let nav = UINavigationController(rootViewController: engagementVC)
        nav.modalPresentationStyle = .pageSheet
        
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        
        present(nav, animated: true) { [weak self] in
            // Resume video after presenting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.playCurrentVideo()
            }
        }
    }
}

// MARK: - ReactionPickerDelegate
extension VideoReelsViewController: ReactionPickerDelegate {
    func reactionPicker(_ picker: ReactionPickerView, didSelectReaction reaction: ReactionStyle) {
        guard let currentCell = collectionView.visibleCells.first as? VideoReelCell,
              let indexPath = collectionView.indexPath(for: currentCell) else { return }
        
        var reel = reels[indexPath.item]
        guard let activityId = reel.activityId else { return }
        
        // Update optimistically
        reel.userActivityReaction = reaction.rawValue
        reel.activityReactionCount = (reel.activityReactionCount ?? 0) + (reel.userActivityReaction == nil ? 1 : 0)
        reels[indexPath.item] = reel
        currentCell.configure(with: reel, player: players[indexPath.item])
        
        // Send reaction to server
        let endpoint = "activities/\(activityId)/reactions"
        let body = ["emoji": reaction.rawValue]
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: body
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            if case .failure(let error) = result {
                print("Failed to add reaction: \(error)")
                // Could revert the optimistic update here
            }
        }
    }
    
    func reactionPickerDidDismiss(_ picker: ReactionPickerView) {
        // Optional: Resume video or perform other cleanup
    }
}

// MARK: - Single Activity Response
struct SingleActivityResponse: Codable {
    let success: Bool
    let data: Activity
}

// MARK: - VideoCommentsViewControllerDelegate
extension VideoReelsViewController: VideoCommentsViewControllerDelegate {
    func videoCommentsDidUpdate(_ controller: VideoCommentsViewController, newCommentCount: Int) {
        // Find the video that was being commented on
        for (index, reel) in reels.enumerated() {
            // Check if this is the video we're commenting on
            if let presentedNav = presentedViewController as? UINavigationController,
               let commentsVC = presentedNav.viewControllers.first as? VideoCommentsViewController,
               commentsVC == controller {
                
                // Update the comment count
                reels[index].commentCount = newCommentCount
                
                // Update the visible cell if it's the current one
                if index == currentIndex,
                   let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? VideoReelCell {
                    // Get the player for this cell
                    let player = reels[index].contentType == "photo" ? nil : players[index]
                    cell.configure(with: reels[index], player: player)
                }
                
                break
            }
        }
    }
}