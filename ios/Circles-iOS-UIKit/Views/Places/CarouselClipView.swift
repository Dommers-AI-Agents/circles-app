import UIKit
import AVFoundation

/// One short clip (a Moment at the place) as a page of the place page's top
/// carousel: its thumbnail, then the clip itself, muted and looping, while it
/// is the page on screen (Wes, 2026-11-12: "scroll through not only images,
/// but short video clips of a place as well"). Tapping the page opens the
/// moment full screen, with sound, likes, comments and Report.
///
/// The player is made on the first `play()`, never at configure time, so a
/// place with many clips doesn't start downloading all of them at once.
final class CarouselClipView: UIView {

    let moment: PlaceVideo

    private final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    private let thumbnailView = UIImageView()
    private let playerView = PlayerView()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    init(moment: PlaceVideo) {
        self.moment = moment
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .black
        clipsToBounds = true

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = Constants.Colors.lightGray
        playerView.playerLayer.videoGravity = .resizeAspectFill
        playerView.isUserInteractionEnabled = false
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
        if let thumb = moment.thumbnailUrl, !thumb.isEmpty {
            ImageService.shared.loadImage(from: thumb) { [weak self] image in
                DispatchQueue.main.async { self?.thumbnailView.image = image }
            }
        }
        addBadge()
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Moment at \(moment.placeName). Opens full screen."
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// "▶ Moment" bottom-left, where a photo's "Photo by" chip sits, so it
    /// reads as a clip even before the video starts
    private func addBadge() {
        let badge = UILabel()
        let text = NSMutableAttributedString(attachment: NSTextAttachment(
            image: UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))!
                .withTintColor(.white, renderingMode: .alwaysOriginal)))
        text.append(NSAttributedString(string: " Moment"))
        badge.attributedText = text
        badge.font = .systemFont(ofSize: 12, weight: .semibold)
        badge.textColor = .white
        let pill = UIView()
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        pill.layer.cornerRadius = 4
        pill.translatesAutoresizingMaskIntoConstraints = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(badge)
        addSubview(pill)
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            badge.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4),
            badge.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
            badge.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            badge.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8)
        ])
    }

    func play() {
        if player == nil {
            // The small preview when there is one: it's what a 6-second muted
            // loop needs, and it starts sooner
            guard let urlString = [moment.previewUrl, moment.videoUrl].compactMap({ $0 }).first(where: { !$0.isEmpty }),
                  let url = URL(string: urlString) else { return }
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            playerView.playerLayer.player = queue
            player = queue
        }
        // Muted, so never interrupt the person's music (see AudioSessionManager)
        AudioSessionManager.shared.allowSilentDecoration()
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    /// Lets go of the player and its download (the page left the carousel)
    func tearDown() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        playerView.playerLayer.player = nil
        player = nil
    }
}
