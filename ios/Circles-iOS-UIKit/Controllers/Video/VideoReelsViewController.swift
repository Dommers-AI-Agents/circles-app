import UIKit
import AVFoundation
import AVKit

class VideoReelsViewController: UIViewController {
    
    // MARK: - Properties
    private var reels: [PlaceVideo]
    private var currentIndex: Int
    private var players: [Int: AVPlayer] = [:]
    private var playerLayers: [Int: AVPlayerLayer] = [:]
    
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
        guard let urlString = reel.videoUrl ?? reel.previewUrl,
              let url = URL(string: urlString) else { return }
        
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none // Loop video
        
        // Add observer for looping
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        
        players[index] = player
    }
    
    private func playCurrentVideo() {
        // Pause all videos first
        pauseAllVideos()
        
        // Play current video
        if let player = players[currentIndex] {
            player.play()
        } else {
            loadVideo(at: currentIndex)
            players[currentIndex]?.play()
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
            body: [:]
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            // Silent tracking, no need to handle response
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
    
    deinit {
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
        
        // Get or create player for this index
        if players[indexPath.item] == nil {
            loadVideo(at: indexPath.item)
        }
        
        if let player = players[indexPath.item] {
            cell.configure(with: reel, player: player)
        }
        
        cell.delegate = self
        
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension VideoReelsViewController: UICollectionViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let center = CGPoint(x: collectionView.frame.size.width / 2 + scrollView.contentOffset.x,
                            y: collectionView.frame.size.height / 2 + scrollView.contentOffset.y)
        
        if let indexPath = collectionView.indexPathForItem(at: center) {
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
        let reel = reels[indexPath.item]
        
        // TODO: Implement like functionality
        print("Like video: \(reel.id)")
    }
    
    func videoReelCellDidTapComment(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // TODO: Implement comment functionality
        print("Comment on video: \(reel.id)")
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
        dismiss(animated: true) {
            // TODO: Navigate to user profile
            print("Show profile for user: \(user.id)")
        }
    }
    
    func videoReelCellDidTapPlace(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Dismiss and show place
        dismiss(animated: true) {
            // TODO: Navigate to place detail
            print("Show place: \(reel.placeId)")
        }
    }
}