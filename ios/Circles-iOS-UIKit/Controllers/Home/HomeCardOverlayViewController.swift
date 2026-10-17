import UIKit

/// The scheduled home card, presented over the home screen.
///
/// The organic cards (a friend's news, the add-place nudge) stay inline: they
/// are ambient and scrollable-past. A card Wes scheduled from the backend is a
/// deliberate message with a window and an audience, so it covers the screen
/// and asks for an answer — Show me, or Skip.
///
/// Everything it shows comes off the wire. Adding a new message is a Firestore
/// write, not a release; only a brand-new *destination* needs the app to ship
/// first. See `backend/services/homeCards.js`.
final class HomeCardOverlayViewController: UIViewController {

    private let card: HomePromptCard
    private let onAct: () -> Void
    private let onSkip: () -> Void
    private let onAlt: () -> Void

    init(card: HomePromptCard, onAct: @escaping () -> Void, onAlt: @escaping () -> Void = {},
         onSkip: @escaping () -> Void) {
        self.card = card
        self.onAct = onAct
        self.onAlt = onAlt
        self.onSkip = onSkip
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private let dimming: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let sheet: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.layer.cornerRadius = 20
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let image: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 14
        view.backgroundColor = Constants.Colors.lightGray
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var actButton = UIButton.primaryButton(title: card.actionLabel)
    private lazy var altButton = UIButton.secondaryButton(title: card.altActionLabel ?? "")
    /// With a second answer on the card, Skip steps back to a text button so
    /// the two real choices read as the choices.
    private lazy var skipButton: UIButton = {
        guard card.altDestination != nil else { return UIButton.secondaryButton(title: card.skipLabel) }
        let button = UIButton.captionLinkButton()
        button.setTitle(card.skipLabel, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.contentHorizontalAlignment = .center
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        view.addSubview(dimming)
        view.addSubview(sheet)
        let hasAlt = card.altDestination != nil
        let stack = UIStackView(arrangedSubviews: hasAlt
            ? [titleLabel, bodyLabel, actButton, altButton, skipButton]
            : [titleLabel, bodyLabel, actButton, skipButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: bodyLabel)
        stack.setCustomSpacing(8, after: actButton)
        stack.setCustomSpacing(4, after: altButton)
        stack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = card.title
        bodyLabel.text = card.body
        bodyLabel.isHidden = card.body.isEmpty

        var constraints: [NSLayoutConstraint] = [
            dimming.topAnchor.constraint(equalTo: view.topAnchor),
            dimming.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimming.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimming.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheet.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ]

        if let urlString = card.imageUrl, !urlString.isEmpty {
            sheet.addSubview(image)
            constraints += [
                image.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 20),
                image.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 20),
                image.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -20),
                image.heightAnchor.constraint(equalTo: image.widthAnchor, multiplier: 0.5),
                stack.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 18)
            ]
            ImageService.shared.loadImage(from: urlString) { [weak self] loaded in
                DispatchQueue.main.async { self?.image.image = loaded }
            }
        } else {
            constraints.append(stack.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 26))
        }

        sheet.addSubview(stack)
        constraints += [
            stack.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: sheet.bottomAnchor, constant: -20)
        ]
        NSLayoutConstraint.activate(constraints)

        actButton.addTarget(self, action: #selector(actTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        altButton.addTarget(self, action: #selector(altTapped), for: .touchUpInside)

        // No tap-to-dismiss on the dimming: an overlay that vanishes on a
        // stray tap would burn the card's one showing without an answer.
    }

    // The pop-in starts in viewWillAppear, alongside the cross-dissolve. Doing
    // it in viewDidAppear hid a card the dissolve had already shown and
    // brought it in again: the card flashed twice.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sheet.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        sheet.alpha = 0
        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4) {
            self.sheet.transform = .identity
            self.sheet.alpha = 1
        }
    }

    @objc private func actTapped() {
        dismiss(animated: true) { [onAct] in onAct() }
    }

    @objc private func altTapped() {
        dismiss(animated: true) { [onAlt] in onAlt() }
    }

    @objc private func skipTapped() {
        dismiss(animated: true) { [onSkip] in onSkip() }
    }
}
