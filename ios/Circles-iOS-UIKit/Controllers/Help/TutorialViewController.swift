import UIKit
import AVKit
import AVFoundation

class TutorialViewController: UIViewController {
    
    // MARK: - Properties
    var startTime: TimeInterval = 0
    private var player: AVPlayer?
    private var playerViewController: AVPlayerViewController?
    private var timeObserver: Any?
    
    // MARK: - UI Elements
    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.text = "Tutorial video not available"
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Try Again", for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var chaptersButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Chapters", for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.addTarget(self, action: #selector(showChapters), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadTutorialVideo()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.pause()
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }
    
    // MARK: - Setup
    private func setupUI() {
        title = "Tutorial Video"
        view.backgroundColor = .black
        
        // Navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Text Version",
            style: .plain,
            target: self,
            action: #selector(showTextVersion)
        )
        
        // Add subviews
        view.addSubview(containerView)
        containerView.addSubview(loadingIndicator)
        containerView.addSubview(errorLabel)
        containerView.addSubview(retryButton)
        view.addSubview(chaptersButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            errorLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -32),
            
            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16),
            retryButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            
            chaptersButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            chaptersButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        
        loadingIndicator.startAnimating()
    }
    
    private func loadTutorialVideo() {
        // Load video from Firebase Storage
        loadRemoteVideo()
    }
    
    private func loadRemoteVideo() {
        // Firebase Storage URL for tutorial video
        // Video should be uploaded to Firebase Storage at: tutorial/tutorial.mov
        let videoURLString = "https://firebasestorage.googleapis.com/v0/b/circles-app-83b67.firebasestorage.app/o/tutorial%2Ftutorial.mov?alt=media"
        
        guard let videoURL = URL(string: videoURLString) else {
            print("Invalid video URL")
            showError()
            return
        }
        
        // Show loading state
        loadingIndicator.startAnimating()
        errorLabel.isHidden = true
        retryButton.isHidden = true
        
        // Setup player with remote URL
        setupPlayer(with: videoURL)
    }
    
    private func setupPlayer(with url: URL) {
        player = AVPlayer(url: url)
        
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        playerVC.showsPlaybackControls = true
        playerVC.allowsPictureInPicturePlayback = true
        
        // Add as child view controller
        addChild(playerVC)
        containerView.addSubview(playerVC.view)
        playerVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            playerVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            playerVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            playerVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            playerVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        playerVC.didMove(toParent: self)
        self.playerViewController = playerVC
        
        loadingIndicator.stopAnimating()
        
        // Seek to start time if specified
        if startTime > 0 {
            let time = CMTime(seconds: startTime, preferredTimescale: 1)
            player?.seek(to: time) { [weak self] _ in
                self?.player?.play()
            }
        } else {
            // Auto-play
            player?.play()
        }
        
        // Add time observer for chapter tracking
        addTimeObserver()
    }
    
    private func addTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // Update UI based on current time if needed
            let seconds = CMTimeGetSeconds(time)
            self?.updateChapterHighlight(for: seconds)
        }
    }
    
    private func updateChapterHighlight(for currentTime: TimeInterval) {
        // Update chapter button or other UI based on current playback position
    }
    
    private func showError() {
        loadingIndicator.stopAnimating()
        errorLabel.text = "Unable to load tutorial video.\nPlease check your internet connection and try again."
        errorLabel.isHidden = false
        retryButton.isHidden = false
        chaptersButton.isHidden = true
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func showTextVersion() {
        let helpVC = HelpViewController()
        let navController = UINavigationController(rootViewController: helpVC)
        present(navController, animated: true)
    }
    
    @objc private func retryLoading() {
        errorLabel.isHidden = true
        retryButton.isHidden = true
        loadingIndicator.startAnimating()
        loadTutorialVideo()
    }
    
    @objc private func showChapters() {
        let alertController = UIAlertController(title: "Video Chapters", message: nil, preferredStyle: .actionSheet)
        
        let chapters: [(String, TimeInterval)] = [
            ("Welcome & Overview", 0),
            ("Creating Circles", 60),
            ("Privacy Settings", 120),
            ("Grouping Circles", 180),
            ("Adding Places", 240),
            ("Searching Places", 300),
            ("Adding Notes", 360),
            ("Connecting with Others", 420),
            ("Following Users", 480),
            ("Creating Moments", 540),
            ("Viewing Moments", 600),
            ("Quick Actions", 660),
            ("Using the Map", 720),
            ("Discovering Places", 780),
            ("Privacy Controls", 840),
            ("Troubleshooting", 900)
        ]
        
        for (title, time) in chapters {
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.seekToTime(time)
            }
            alertController.addAction(action)
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // iPad support
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = chaptersButton
            popover.sourceRect = chaptersButton.bounds
        }
        
        present(alertController, animated: true)
    }
    
    private func seekToTime(_ time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1)
        player?.seek(to: cmTime) { [weak self] _ in
            self?.player?.play()
        }
    }
}

// MARK: - Tutorial Text Version
extension TutorialViewController {
    private func showFullTextTutorial() {
        let textVC = TutorialTextViewController()
        navigationController?.pushViewController(textVC, animated: true)
    }
}

// MARK: - Tutorial Text View Controller
class TutorialTextViewController: BaseViewController {
    
    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = Constants.Colors.label
        textView.backgroundColor = Constants.Colors.background
        textView.contentInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadContent()
    }
    
    private func setupUI() {
        title = "Tutorial Guide"
        view.backgroundColor = Constants.Colors.background
        
        view.addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadContent() {
        let content = """
        # Welcome to Circles Tutorial
        
        This guide will walk you through all the features of Circles.
        
        ## Getting Started
        
        Circles is your personal recommendation platform for sharing favorite places with your network.
        
        ### Creating Your First Circle
        1. Tap the + button on the home screen
        2. Select "Create Circle"
        3. Give it a meaningful name
        4. Choose a category
        5. Set your privacy preference
        
        ### Adding Places
        • Search for places by name
        • Browse nearby locations
        • Add from the map view
        • Include personal notes
        
        ### Building Your Network
        • Connect with friends
        • Follow other users
        • Share your circles
        • Discover new places
        
        ### Creating Moments
        • Share photos and videos
        • Tag places you visit
        • Build visual stories
        
        For more detailed help on any topic, visit the Help section in Settings.
        """
        
        textView.text = content
    }
}