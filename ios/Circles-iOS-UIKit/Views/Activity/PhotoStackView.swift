import UIKit

/// A few photos as a fanned stack (2026-11-16): up to three cards, the top
/// one straight, the ones behind turned a little, with a "7 photos" badge.
/// Swiping sideways brings the next photo to the front; `fanOpen()` is the
/// card's first-appearance moment (the stack starts square and fans out).
final class PhotoStackView: UIView {
    private var urls: [String] = []
    private var cards: [UIImageView] = []
    private var front = 0
    private let badge = PaddedPillLabel()
    private var loadIds: [ObjectIdentifier: String] = [:]
    var onTap: ((String) -> Void)?

    /// The resting angles, back to front
    private static let angles: [CGFloat] = [-6, 5, 0]

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        for _ in 0..<3 {
            let card = UIImageView()
            card.contentMode = .scaleAspectFill
            card.clipsToBounds = true
            card.layer.cornerRadius = 14
            card.layer.cornerCurve = .continuous
            card.backgroundColor = Constants.Colors.lightGray
            card.layer.borderWidth = 3
            card.layer.borderColor = UIColor.white.cgColor
            card.isHidden = true
            addSubview(card)
            cards.append(card)
        }
        badge.font = .systemFont(ofSize: 12, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(advance))
        swipeLeft.direction = .left
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(advance))
        swipeRight.direction = .right
        addGestureRecognizer(swipeLeft)
        addGestureRecognizer(swipeRight)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(urls: [String]) {
        self.urls = urls
        front = 0
        badge.text = urls.count > 1 ? "\(urls.count) photos" : nil
        badge.isHidden = urls.count <= 1
        layoutCards(animated: false)
        loadImages()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = urls.count > 1 ? 14 : 0
        let frame = bounds.insetBy(dx: inset, dy: inset)
        for card in cards {
            // Keep the rotation: set bounds and centre, never the frame
            card.bounds = CGRect(origin: .zero, size: frame.size)
            card.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    /// Which url each visible card shows: the front card is `front`, the
    /// ones behind are the next in line
    private func visibleUrls() -> [String] {
        guard !urls.isEmpty else { return [] }
        let count = min(3, urls.count)
        return (0..<count).map { urls[(front + $0) % urls.count] }.reversed() // back first
    }

    private func loadImages() {
        let visible = visibleUrls()
        for (index, card) in cards.enumerated() {
            guard index < visible.count else { card.isHidden = true; card.image = nil; continue }
            card.isHidden = false
            let url = visible[index]
            let loadId = UUID().uuidString
            loadIds[ObjectIdentifier(card)] = loadId
            card.image = nil
            ImageService.shared.loadImageWithKey(from: url, cacheKey: "activity_stack_\(url)") { [weak self, weak card] image in
                DispatchQueue.main.async {
                    guard let self, let card, self.loadIds[ObjectIdentifier(card)] == loadId else { return }
                    card.image = image
                }
            }
        }
    }

    private func layoutCards(animated: Bool, fanned: Bool = true) {
        let visible = visibleUrls().count
        let apply = {
            for (index, card) in self.cards.enumerated() {
                guard index < visible else { continue }
                // The angles for the number of cards showing: the front one is always straight
                let slot = Self.angles.count - visible + index
                let angle = fanned ? Self.angles[slot] : 0
                card.transform = CGAffineTransform(rotationAngle: angle * .pi / 180)
                card.alpha = 1
            }
        }
        if animated {
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.4, options: [.allowUserInteraction], animations: apply)
        } else {
            apply()
        }
        bringSubviewToFront(badge)
    }

    /// The first-appearance moment: square, then fanned
    func fanOpen() {
        guard urls.count > 1, !UIAccessibility.isReduceMotionEnabled else { return }
        layoutCards(animated: false, fanned: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.layoutCards(animated: true) }
    }

    @objc private func advance() {
        guard urls.count > 1 else { return }
        front = (front + 1) % urls.count
        UISelectionFeedbackGenerator().selectionChanged()
        loadImages()
        layoutCards(animated: false, fanned: false)
        layoutCards(animated: true)
    }

    @objc private func tapped() {
        guard !urls.isEmpty else { return }
        onTap?(urls[front % urls.count])
    }

    func reset() {
        urls = []
        loadIds = [:]
        for card in cards { card.isHidden = true; card.image = nil; card.transform = .identity }
        badge.isHidden = true
    }
}
