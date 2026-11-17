import UIKit
import AVFoundation

/// A moment's clip on an Activity card: its thumbnail, then the clip itself
/// looping muted while the card is the one in focus (2026-11-16). The player
/// is made on the first `play()`, never at configure time, and dropped when
/// the card leaves the screen, so a feed full of moments downloads one at a
/// time. The thumbnail cross-fades into the first frame.
final class ActivityClipView: UIView {

    private final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    private let thumbnailView = UIImageView()
    private let playerView = PlayerView()
    private let badge = UIImageView(image: UIImage(systemName: "play.circle.fill"))
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private(set) var clipURL: URL?
    private var thumbnailLoadId: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        playerView.playerLayer.videoGravity = .resizeAspectFill
        playerView.isUserInteractionEnabled = false
        playerView.alpha = 0
        for view in [thumbnailView, playerView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        badge.tintColor = UIColor.white.withAlphaComponent(0.92)
        badge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(thumbnail: String, clip: String?) {
        stop()
        clipURL = clip.flatMap(URL.init(string:))
        badge.isHidden = false
        thumbnailView.image = nil
        let loadId = UUID().uuidString
        thumbnailLoadId = loadId
        ImageService.shared.loadImage(from: thumbnail) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.thumbnailLoadId == loadId else { return }
                self.thumbnailView.image = image
            }
        }
    }

    var isPlaying: Bool { player?.rate ?? 0 > 0 }

    /// Starts the loop (makes the player the first time); the thumbnail fades
    /// out once the first frame is up
    func play() {
        guard let url = clipURL else { return }
        if let player {
            player.play()
            return
        }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: queue, templateItem: item)
        playerView.playerLayer.player = queue
        player = queue
        readyObservation = playerView.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.4) {
                    self.playerView.alpha = 1
                    self.badge.alpha = 0
                }
            }
        }
        queue.play()
    }

    func pause() { player?.pause() }

    /// Drops the player: the card left the screen or is being reused
    func stop() {
        readyObservation = nil
        player?.pause()
        looper = nil
        playerView.playerLayer.player = nil
        player = nil
        playerView.alpha = 0
        badge.alpha = 1
    }
}
