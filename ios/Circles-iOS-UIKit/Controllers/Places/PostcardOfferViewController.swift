import UIKit

/// "Send it as a postcard?" after a photo upload or a save with your own
/// photo (Wes, 2026-10-17: the plain alert was ugly and didn't sell it).
/// Shows the photo already dressed as a postcard, what you can do with it,
/// and Make my postcard / Not now / Learn more.
final class PostcardOfferViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    private let placeName: String
    private let photo: UIImage?
    private let photoUrl: String?
    private let onMake: () -> Void
    private let onDecline: () -> Void
    /// The pop-in runs once (coming back from Learn more doesn't replay it)
    private var hasAnimatedIn = false

    init(placeName: String, photo: UIImage?, photoUrl: String?,
         onMake: @escaping () -> Void, onDecline: @escaping () -> Void) {
        self.placeName = placeName
        self.photo = photo
        self.photoUrl = photoUrl
        self.onMake = onMake
        self.onDecline = onDecline
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Views

    private let dimming: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let sheet: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.layer.cornerRadius = 22
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// The card itself: white paper border, photo, "Greetings from", stamp
    private let card: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 6
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.25
        view.layer.shadowRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 6)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let photoView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = Constants.Colors.lightGray
        view.layer.cornerRadius = 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let fade: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.55).cgColor]
        layer.locations = [0.45, 1]
        return layer
    }()

    private lazy var greeting: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        let text = NSMutableAttributedString(string: "Greetings from\n", attributes: [
            .font: UIFont.italicSystemFont(ofSize: 13), .foregroundColor: UIColor.white
        ])
        text.append(NSAttributedString(string: placeName, attributes: [
            .font: UIFont.systemFont(ofSize: 22, weight: .heavy), .foregroundColor: UIColor.white
        ]))
        label.attributedText = text
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.4
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = .zero
        return label
    }()

    private let stamp: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.borderColor = Constants.Colors.primary.cgColor
        view.layer.borderWidth = 2
        view.layer.cornerRadius = 3
        view.transform = CGAffineTransform(rotationAngle: 0.08)
        view.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "heart.circle.fill"))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            icon.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6),
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor)
        ])
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Turn this photo into a postcard"
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var makeButton = UIButton.primaryButton(title: "Make my postcard")
    private lazy var notNowButton = UIButton.secondaryButton(title: "Not now")
    private lazy var learnMoreButton: UIButton = {
        let button = UIButton.captionLinkButton()
        button.setTitle("Learn more about postcards", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.contentHorizontalAlignment = .center
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }()

    /// One selling point: symbol + line
    private func point(_ symbol: String, _ text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 12
        row.alignment = .center
        return row
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(dimming)
        view.addSubview(sheet)

        card.addSubview(photoView)
        photoView.layer.addSublayer(fade)
        card.addSubview(greeting)
        card.addSubview(stamp)
        let cardHolder = UIView()
        cardHolder.addSubview(card)

        let points = UIStackView(arrangedSubviews: [
            point("paperplane.fill", "Send it free to friends on FavCircles, by email or by text"),
            point("envelope.fill", "Or we print and mail a real 4\u{00D7}6 card anywhere in the US"),
            point("pencil.line", "Add a note on the back. It takes about a minute")
        ])
        points.axis = .vertical
        points.spacing = 10

        let stack = UIStackView(arrangedSubviews: [cardHolder, titleLabel, points, makeButton, notNowButton, learnMoreButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(26, after: cardHolder)
        stack.setCustomSpacing(16, after: titleLabel)
        stack.setCustomSpacing(22, after: points)
        stack.setCustomSpacing(8, after: makeButton)
        stack.setCustomSpacing(4, after: notNowButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(stack)

        NSLayoutConstraint.activate([
            dimming.topAnchor.constraint(equalTo: view.topAnchor),
            dimming.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimming.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimming.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheet.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sheet.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            sheet.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            sheet.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            stack.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: sheet.bottomAnchor, constant: -16),

            // A 3:2 postcard, a little narrower than the sheet so the tilt fits
            card.centerXAnchor.constraint(equalTo: cardHolder.centerXAnchor),
            card.topAnchor.constraint(equalTo: cardHolder.topAnchor, constant: 6),
            card.bottomAnchor.constraint(equalTo: cardHolder.bottomAnchor, constant: -6),
            card.widthAnchor.constraint(equalTo: cardHolder.widthAnchor, multiplier: 0.88),
            card.heightAnchor.constraint(equalTo: card.widthAnchor, multiplier: 2.0 / 3.0),

            photoView.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            photoView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            photoView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            photoView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),

            greeting.leadingAnchor.constraint(equalTo: photoView.leadingAnchor, constant: 12),
            greeting.trailingAnchor.constraint(lessThanOrEqualTo: stamp.leadingAnchor, constant: -8),
            greeting.bottomAnchor.constraint(equalTo: photoView.bottomAnchor, constant: -10),

            stamp.topAnchor.constraint(equalTo: photoView.topAnchor, constant: 10),
            stamp.trailingAnchor.constraint(equalTo: photoView.trailingAnchor, constant: -10),
            stamp.widthAnchor.constraint(equalToConstant: 34),
            stamp.heightAnchor.constraint(equalToConstant: 40)
        ])
        card.transform = CGAffineTransform(rotationAngle: -0.035)

        if let photo {
            photoView.image = photo
        } else if let photoUrl, !photoUrl.isEmpty {
            ImageService.shared.loadImage(from: photoUrl) { [weak self] image in
                DispatchQueue.main.async { self?.photoView.image = image }
            }
        }

        makeButton.addTarget(self, action: #selector(makeTapped), for: .touchUpInside)
        notNowButton.addTarget(self, action: #selector(notNowTapped), for: .touchUpInside)
        learnMoreButton.addTarget(self, action: #selector(learnMoreTapped), for: .touchUpInside)
        // No tap-outside dismiss: a stray tap shouldn't spend the offer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fade.frame = photoView.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        sheet.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        sheet.alpha = 0
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4) {
            self.sheet.transform = .identity
            self.sheet.alpha = 1
        }
    }

    // MARK: - Actions

    @objc private func makeTapped() {
        dismiss(animated: true) { [onMake] in onMake() }
    }

    @objc private func notNowTapped() {
        dismiss(animated: true) { [onDecline] in onDecline() }
    }

    /// The help article in a sheet over this one; closing it comes back here
    @objc private func learnMoreTapped() {
        AnalyticsService.shared.logEvent("postcard_nudge_learn_more")
        guard let topic = HelpContentProvider.shared.topic(withId: "postcards") else { return }
        let help = HelpTopicViewController(topic: topic)
        help.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done, primaryAction: UIAction { [weak help] _ in help?.dismiss(animated: true) })
        let nav = UINavigationController(rootViewController: help)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }
}
