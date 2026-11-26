import UIKit

// The first screen after Open at a store's window code (Wes, 2026-11-26):
// "Welcome to <store>", the store's photo, what staying connected brings
// (rewards where they're live, the menu, specials, events, announcements),
// and one button: "Save <store> & stay connected". The same layout at every
// store; the words and rows come from the server (ClipExperience), so the
// owner's changes show at the next scan with no new build. Rows only promise
// what's coming: never a count, a date, or "nothing yet".
final class ClipStoreWelcomeViewController: UIViewController {

    private let invocation: ClipInvocation
    private let preview: VenuePreview
    private let experience: ClipExperience

    private let photoView = UIImageView()
    private let photoFade = CAGradientLayer()
    private let brandMark = ClipTheme.brandMarkView(side: 36)
    private lazy var brandHeader = ClipTheme.brandHeader(mark: brandMark)
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private lazy var saveButton = ClipTheme.primaryButton(experience.welcome.button)
    private let footLabel = ClipTheme.label(.systemFont(ofSize: 13, weight: .medium), color: UIColor.white.withAlphaComponent(0.72))

    init(invocation: ClipInvocation, preview: VenuePreview, experience: ClipExperience) {
        self.invocation = invocation
        self.preview = preview
        self.experience = experience
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ClipTheme.charcoal
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupUI()
        Task { await loadPhoto() }
        #if DEBUG
        ClipAutopilot.shared?.ready(self)
        #endif
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        photoFade.frame = photoView.bounds
    }

    private func setupUI() {
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.backgroundColor = ClipTheme.ink
        photoView.translatesAutoresizingMaskIntoConstraints = false
        // Dark behind the header, clear in the middle, into the page below
        photoFade.colors = [UIColor.black.withAlphaComponent(0.45).cgColor,
                            UIColor.clear.cgColor,
                            ClipTheme.charcoal.withAlphaComponent(0.6).cgColor,
                            ClipTheme.charcoal.cgColor]
        photoFade.locations = [0, 0.25, 0.7, 1]
        photoView.layer.addSublayer(photoFade)
        view.addSubview(photoView)
        view.addSubview(brandHeader)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let hook = ClipTheme.label(ClipTheme.serif(36))
        hook.attributedText = ClipTheme.hookText("Welcome to", experience.welcome.title, size: 36)
        hook.adjustsFontSizeToFitWidth = true
        hook.minimumScaleFactor = 0.6
        ClipTheme.lift(hook)
        stack.addArrangedSubview(hook)

        if let rating = experience.welcome.ratingLine {
            let ratingLabel = ClipTheme.label(.systemFont(ofSize: 15, weight: .semibold), color: ClipTheme.gold)
            ratingLabel.text = "\u{2605} \(rating)"
            ClipTheme.lift(ratingLabel)
            stack.addArrangedSubview(ratingLabel)
        }

        let line = ClipTheme.label(.systemFont(ofSize: 17), color: UIColor.white.withAlphaComponent(0.92))
        line.text = experience.welcome.line
        stack.addArrangedSubview(line)
        stack.setCustomSpacing(16, after: line)

        for row in experience.welcome.rows {
            stack.addArrangedSubview(rowView(row))
        }

        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        saveButton.accessibilityIdentifier = "clipSaveAndConnect"
        saveButton.titleLabel?.adjustsFontSizeToFitWidth = true
        footLabel.text = "Free \u{00b7} no password \u{00b7} turn alerts off any time"
        footLabel.textAlignment = .center
        let bottom = UIStackView(arrangedSubviews: [saveButton, footLabel])
        bottom.axis = .vertical
        bottom.spacing = 8
        bottom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottom)

        NSLayoutConstraint.activate([
            photoView.topAnchor.constraint(equalTo: view.topAnchor),
            photoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            photoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            photoView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.42),

            brandHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            brandHeader.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 22),
            brandHeader.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -22),

            // The words start over the bottom of the photo
            scrollView.topAnchor.constraint(equalTo: photoView.bottomAnchor, constant: -110),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -10),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -22),

            bottom.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 22),
            bottom.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -22),
            bottom.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
        ClipTheme.animateIn([brandHeader, stack, bottom])
    }

    /// Icon tile, title, one line; the menu row opens the menu
    private func rowView(_ row: ClipExperience.Row) -> UIView {
        let tile = UIView()
        tile.backgroundColor = ClipTheme.gold.withAlphaComponent(0.18)
        tile.layer.cornerRadius = 10
        tile.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: Self.symbol(for: row.kind),
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
        icon.tintColor = ClipTheme.gold
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(icon)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 38),
            tile.heightAnchor.constraint(equalToConstant: 38),
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor)
        ])

        let title = ClipTheme.label(.systemFont(ofSize: 16, weight: .semibold), lines: 1)
        title.text = row.title
        let detail = ClipTheme.label(.systemFont(ofSize: 14), color: UIColor.white.withAlphaComponent(0.78))
        detail.text = row.detail
        let words = UIStackView(arrangedSubviews: [title, detail])
        words.axis = .vertical
        words.spacing = 1

        var parts: [UIView] = [tile, words]
        if row.url != nil {
            let chevron = UIImageView(image: UIImage(systemName: "arrow.up.right"))
            chevron.tintColor = UIColor.white.withAlphaComponent(0.6)
            chevron.setContentHuggingPriority(.required, for: .horizontal)
            parts.append(chevron)
        }
        let line = UIStackView(arrangedSubviews: parts)
        line.spacing = 12
        line.alignment = .center
        line.isLayoutMarginsRelativeArrangement = true
        line.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

        let card = UIControl()
        card.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        card.layer.cornerRadius = 14
        line.isUserInteractionEnabled = false
        line.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: card.topAnchor),
            line.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])
        if let url = row.url.flatMap(URL.init(string:)) {
            card.accessibilityTraits = .link
            card.addAction(UIAction { _ in UIApplication.shared.open(url) }, for: .touchUpInside)
        }
        card.isAccessibilityElement = true
        card.accessibilityLabel = "\(row.title). \(row.detail)"
        return card
    }

    static func symbol(for kind: String) -> String {
        switch kind {
        case "rewards": return "star.fill"
        case "menu": return "menucard"
        case "specials": return "tag.fill"
        case "events": return "calendar"
        case "announcements": return "megaphone.fill"
        default: return "heart.fill"
        }
    }

    private func loadPhoto() async {
        guard let url = (experience.welcome.photoUrl ?? preview.coverUrl).flatMap(URL.init(string:)),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        photoView.alpha = 0
        photoView.image = image
        UIView.animate(withDuration: 0.4) { self.photoView.alpha = 1 }
    }

    /// On to sign-in, over a second photo of the store
    @objc func saveTapped() {
        let connect = ClipOfferViewController(invocation: invocation, connectingTo: preview)
        navigationController?.pushViewController(connect, animated: true)
    }
}
