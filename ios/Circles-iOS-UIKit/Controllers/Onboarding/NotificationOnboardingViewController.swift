import UIKit
import UserNotifications

/// First-session notification ask (Wes, 2026-10-09: "we want them to
/// accept notifications"; 2026-11-01: "make it a pretty page", it was ugly
/// and too wordy). Shows what they'd get instead of explaining it: three
/// sample notifications slide in over the brand gradient, one line of copy,
/// one big button. A no is respected without an extra alert.
final class NotificationOnboardingViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    var onCompletion: (() -> Void)?
    private var finished = false
    /// The store they joined at (App Clip): the page leads with it
    var storeName: String?
    /// "Stores I follow only" (2026-11-26): they choose just their stores
    /// (selected) or everything, once
    private lazy var asksScope = NotificationScopeStore.shared.shouldAsk(.tour)
    private var wantsEverything = false
    private let justStoresOption = UIButton(type: .system)
    private let everythingOption = UIButton(type: .system)

    private let gradient = CAGradientLayer()
    private let bubbles = UIStackView()
    private lazy var allowButton = UIButton.primaryButton(title: "Turn on notifications")
    private let skipButton = UIButton(type: .system)

    /// What a notification from FavCircles looks like (illustrations only)
    private static let samples: [(symbol: String, title: String, body: String)] = [
        ("mappin.circle.fill", "New near you", "Brittany saved a new favorite 0.4 mi away"),
        ("paperplane.fill", "A place for you", "Wesley sent you Kanna: \u{201C}you\u{2019}ll love their lattes\u{201D}"),
        ("gift.fill", "Rewards", "+25 points at your favorite bakery")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        navigationController?.setNavigationBarHidden(true, animated: false)
        gradient.colors = [UIColor(red: 0.04, green: 0.09, blue: 0.20, alpha: 1).cgColor,
                           Constants.Colors.primary.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer.insertSublayer(gradient, at: 0)
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The sample notifications drop in one after another
        for (index, bubble) in bubbles.arrangedSubviews.enumerated() {
            UIView.animate(withDuration: 0.55, delay: 0.25 + Double(index) * 0.45,
                           usingSpringWithDamping: 0.78, initialSpringVelocity: 0.4) {
                bubble.alpha = 1
                bubble.transform = .identity
            }
        }
    }

    private func setupUI() {
        bubbles.axis = .vertical
        bubbles.spacing = 10
        let samples = asksScope ? Self.storeSamples(storeName) : Self.samples
        for sample in samples {
            let bubble = Self.bubble(symbol: sample.symbol, title: sample.title, body: sample.body)
            bubble.alpha = 0
            bubble.transform = CGAffineTransform(translationX: 0, y: -24).scaledBy(x: 0.96, y: 0.96)
            bubbles.addArrangedSubview(bubble)
        }
        bubbles.isAccessibilityElement = false
        bubbles.accessibilityElementsHidden = true

        let title = UILabel()
        title.text = asksScope ? "Hear from \(storeName ?? "your stores")" : "Never miss a new favorite"
        title.font = Self.serif(34)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .white
        title.numberOfLines = 0
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = asksScope
            ? "Their specials, events and news, at most one a day."
            : "Friends\u{2019} new spots, places sent to you, and your rewards."
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = UIColor.white.withAlphaComponent(0.85)
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        allowButton.backgroundColor = .white
        allowButton.setTitleColor(UIColor(red: 0.04, green: 0.09, blue: 0.20, alpha: 1), for: .normal)
        allowButton.layer.cornerRadius = 16
        allowButton.addTarget(self, action: #selector(allowTapped), for: .touchUpInside)
        skipButton.setTitle("Not now", for: .normal)
        skipButton.setTitleColor(UIColor.white.withAlphaComponent(0.8), for: .normal)
        skipButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)

        var wordViews: [UIView] = [title, subtitle]
        if asksScope {
            configureOption(justStoresOption, title: "Just the stores I follow",
                            detail: "\(storeName ?? "Your stores")\u{2019}s specials, events and news")
            configureOption(everythingOption, title: "Everything",
                            detail: "Also when friends save places, send you suggestions or follow you")
            justStoresOption.addAction(UIAction { [weak self] _ in self?.pickEverything(false) }, for: .touchUpInside)
            everythingOption.addAction(UIAction { [weak self] _ in self?.pickEverything(true) }, for: .touchUpInside)
            let options = UIStackView(arrangedSubviews: [justStoresOption, everythingOption])
            options.axis = .vertical
            options.spacing = 8
            wordViews.append(options)
            pickEverything(false)
        }
        let words = UIStackView(arrangedSubviews: wordViews)
        words.axis = .vertical
        words.spacing = 10
        let buttons = UIStackView(arrangedSubviews: [allowButton, skipButton])
        buttons.axis = .vertical
        buttons.spacing = 8

        [bubbles, words, buttons].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bubbles.topAnchor.constraint(equalTo: guide.topAnchor, constant: 60),
            bubbles.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            bubbles.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            words.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 28),
            words.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -28),
            words.topAnchor.constraint(equalTo: bubbles.bottomAnchor, constant: 44),
            words.bottomAnchor.constraint(lessThanOrEqualTo: buttons.topAnchor, constant: -24),
            buttons.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12)
        ])
    }

    /// What a store's alerts look like (illustrations only)
    private static func storeSamples(_ name: String?) -> [(symbol: String, title: String, body: String)] {
        let store = name ?? "Your favorite store"
        return [
            ("tag.fill", store, "New special just posted"),
            ("calendar", store, "This Saturday: an event for regulars")
        ]
    }

    private func configureOption(_ button: UIButton, title: String, detail: String) {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.12)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.titleAlignment = .leading
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        config.imagePlacement = .trailing
        config.imagePadding = 10
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
        config.attributedSubtitle = AttributedString(detail, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 14)]))
        button.configuration = config
        button.contentHorizontalAlignment = .fill
    }

    private func pickEverything(_ everything: Bool) {
        wantsEverything = everything
        for (button, selected) in [(justStoresOption, !everything), (everythingOption, everything)] {
            button.configuration?.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
            button.configuration?.baseBackgroundColor = UIColor.white.withAlphaComponent(selected ? 0.24 : 0.1)
            button.configuration?.background.strokeColor = selected ? .white : UIColor.white.withAlphaComponent(0.25)
            button.configuration?.background.strokeWidth = selected ? 2 : 1
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    /// A sample notification: app icon, a title, one line
    private static func bubble(symbol: String, title: String, body: String) -> UIView {
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
        card.layer.cornerRadius = 20
        card.clipsToBounds = true

        let icon = UIImageView(image: UIImage(systemName: symbol,
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)))
        icon.contentMode = .center
        icon.layer.cornerRadius = 9
        icon.clipsToBounds = true
        icon.backgroundColor = Constants.Colors.primary
        icon.tintColor = .white

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .black
        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = UIColor.black.withAlphaComponent(0.8)
        bodyLabel.numberOfLines = 2
        let text = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        text.axis = .vertical
        text.spacing = 2

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            row.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -14)
        ])
        return card
    }

    private static func serif(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    // MARK: - Actions

    @objc private func allowTapped() {
        allowButton.isEnabled = false
        skipButton.isEnabled = false
        NotificationService.shared.requestNotificationPermissions { [weak self] granted in
            DispatchQueue.main.async {
                AnalyticsService.shared.logEvent("onboarding_notifications_answered", parameters: ["granted": granted ? "1" : "0"])
                if granted { UIApplication.shared.registerForRemoteNotifications() }
                self?.finish()
            }
        }
    }

    @objc private func skipTapped() {
        AnalyticsService.shared.logEvent("permission_primer_skipped", parameters: ["kind": "NotificationOnboardingViewController"])
        finish()
    }

    /// Ends this step exactly once and moves the chain on
    func finish() {
        guard !finished else { return }
        finished = true
        if asksScope { NotificationScopeStore.shared.recordTourAnswer(everything: wantsEverything) }
        UserDefaults.standard.set(true, forKey: "hasShownNotificationOnboarding")
        onCompletion?()
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
