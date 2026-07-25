import UIKit

/// Full-screen congratulations moment shown once when the user's saved-place
/// count reaches a new PlaceMilestone tier (5, 10, 20, 50, ...). Presented
/// over the current screen by PlaceMilestones.celebrateIfNeeded.
class MilestoneCelebrationViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let milestone: PlaceMilestone

    init(milestone: PlaceMilestone) {
        self.milestone = milestone
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Elements

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.layer.cornerRadius = 20
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 44
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Congratulations! 🎉"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let badgeNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let badgePillView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 14
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var continueButton = UIButton.primaryButton(title: "Keep Exploring")
    private lazy var shareButton = UIButton.secondaryButton(title: "Share the News")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        setupCard()
        configureContent()
        startConfetti()
    }

    // MARK: - Setup

    private func setupCard() {
        view.addSubview(cardView)
        cardView.addSubview(iconContainer)
        iconContainer.addSubview(iconView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(messageLabel)
        cardView.addSubview(badgePillView)
        badgePillView.addSubview(badgeNameLabel)
        cardView.addSubview(shareButton)
        cardView.addSubview(continueButton)

        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            iconContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 32),
            iconContainer.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 88),
            iconContainer.heightAnchor.constraint(equalToConstant: 88),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            badgePillView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
            badgePillView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            badgePillView.heightAnchor.constraint(equalToConstant: 28),

            badgeNameLabel.leadingAnchor.constraint(equalTo: badgePillView.leadingAnchor, constant: 14),
            badgeNameLabel.trailingAnchor.constraint(equalTo: badgePillView.trailingAnchor, constant: -14),
            badgeNameLabel.centerYAnchor.constraint(equalTo: badgePillView.centerYAnchor),

            shareButton.topAnchor.constraint(equalTo: badgePillView.bottomAnchor, constant: 24),
            shareButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            shareButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            continueButton.topAnchor.constraint(equalTo: shareButton.bottomAnchor, constant: 12),
            continueButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            continueButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            continueButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24)
        ])
    }

    private func configureContent() {
        iconContainer.backgroundColor = milestone.color
        iconView.image = UIImage(systemName: milestone.iconName)
        badgePillView.backgroundColor = milestone.color
        badgeNameLabel.text = milestone.name.uppercased()

        if milestone.threshold == PlaceMilestones.all.first?.threshold {
            messageLabel.text = "You added your first \(milestone.threshold) places! The \(milestone.name) badge now shows on your profile."
        } else {
            messageLabel.text = "You've added \(milestone.threshold) places! The \(milestone.name) badge now shows on your profile."
        }
    }

    // MARK: - Confetti

    private func startConfetti() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: -20)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: view.bounds.width, height: 1)
        emitter.birthRate = 1

        let colors: [UIColor] = [.systemTeal, .systemPink, .systemYellow,
                                 .systemGreen, .systemOrange, .systemPurple]
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.birthRate = 6
            cell.lifetime = 6
            cell.velocity = 160
            cell.velocityRange = 60
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 6
            cell.spin = 3
            cell.spinRange = 4
            cell.scale = 0.05
            cell.scaleRange = 0.03
            cell.color = color.cgColor
            cell.contents = UIImage(systemName: "circle.fill")?.cgImage
            return cell
        }

        view.layer.addSublayer(emitter)

        // Stop emitting after a few seconds; existing particles fall out naturally
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            emitter.birthRate = 0
        }
    }

    // MARK: - Actions

    @objc private func shareTapped() {
        // Achievement moments are peak share intent — one tap spreads the app
        let shareText = "I just earned the \(milestone.name) badge on Circles — \(milestone.threshold) favorite places saved! 🎉"
        let activityVC = UIActivityViewController(
            activityItems: [shareText, ShareLinks.appStoreURL],
            applicationActivities: nil
        )
        activityVC.popoverPresentationController?.sourceView = shareButton
        present(activityVC, animated: true)
    }

    @objc private func continueTapped() {
        dismiss(animated: true)
    }
}
