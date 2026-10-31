import UIKit

/// The app's first screen after the App Clip (Wes, 2026-10-31): over the
/// store's page, what they earned there, how to keep earning and what the
/// store's points buy, then Save the store or See my rewards. Same look as
/// the clip: charcoal, the serif hook with its second line in gold.
final class ClipWelcomeViewController: BaseViewController {

    private static let charcoal = UIColor(red: 0.18, green: 0.20, blue: 0.23, alpha: 1)
    private static let ink = UIColor(red: 0.07, green: 0.075, blue: 0.09, alpha: 1)
    private static let gold = UIColor(red: 0.965, green: 0.788, blue: 0.271, alpha: 1)

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    var onSave: (() -> Void)?
    var onSeeRewards: (() -> Void)?

    private let welcome: ClipWelcome
    private var safetyEmail: String?
    private let gradient = CAGradientLayer()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    init(welcome: ClipWelcome) {
        self.welcome = welcome
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        gradient.colors = [Self.charcoal.cgColor, Self.ink.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(gradient, at: 0)
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24)
        ])

        let name = welcome.venue.venueName
        let balance = welcome.venueBalance ?? 0
        let hook = UILabel()
        hook.numberOfLines = 0
        if let points = welcome.awardedPoints, points > 0 {
            hook.attributedText = Self.hook("Welcome to FavCircles.", "+\(points) points.")
        } else {
            hook.attributedText = Self.hook("Welcome to FavCircles.", "Build your map.")
        }
        stack.addArrangedSubview(hook)

        let place = Self.label(.systemFont(ofSize: 20, weight: .semibold))
        place.text = name
        stack.addArrangedSubview(place)
        stack.setCustomSpacing(4, after: place)

        let detail = Self.label(.systemFont(ofSize: 16), color: UIColor.white.withAlphaComponent(0.85))
        if welcome.earnRate != nil {
            detail.text = "You have \(balance) points at \(name)."
        } else {
            detail.text = "Save \(name) to one of your circles so it's always on your map."
        }
        stack.addArrangedSubview(detail)
        stack.setCustomSpacing(20, after: detail)

        if let rate = welcome.earnRate {
            stack.addArrangedSubview(Self.heading("KEEP EARNING"))
            let how = Self.label(.systemFont(ofSize: 16, weight: .medium))
            how.text = "Every visit earns \(rate) points. Scan the code at the register, right in the app or with your camera."
            stack.addArrangedSubview(how)
            stack.setCustomSpacing(20, after: how)
        }

        let offers = welcome.offers.sorted { $0.pointsCost < $1.pointsCost }
        if !offers.isEmpty {
            stack.addArrangedSubview(Self.heading("REWARDS AT \(name.uppercased())"))
            for offer in offers {
                stack.addArrangedSubview(rewardRow(offer, balance: balance))
            }
            if let next = welcome.nextRewardLine {
                let line = Self.label(.systemFont(ofSize: 14), color: UIColor.white.withAlphaComponent(0.75))
                line.text = next
                stack.addArrangedSubview(line)
            }
            let spend = Self.label(.systemFont(ofSize: 14), color: UIColor.white.withAlphaComponent(0.75))
            spend.text = "Ready to spend? Open My Rewards at the counter and pick one."
            stack.addArrangedSubview(spend)
            stack.setCustomSpacing(22, after: spend)
        }

        // Joined in the clip with just an email: keep the account
        if let email = AccountSafetyPrompt.stashedEmail {
            AccountSafetyPrompt.markAsked()
            stack.addArrangedSubview(Self.heading("KEEP YOUR POINTS SAFE"))
            let why = Self.label(.systemFont(ofSize: 15), color: UIColor.white.withAlphaComponent(0.85))
            why.text = "You joined with \(email). Set up Face ID so you can always sign back in, or confirm your email."
            stack.addArrangedSubview(why)
            let faceID = UIButton.secondaryButton(title: "Use Face ID to sign in")
            faceID.setTitleColor(.white, for: .normal)
            faceID.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
            faceID.layer.cornerRadius = 14
            faceID.addTarget(self, action: #selector(faceIDTapped), for: .touchUpInside)
            let confirm = UIButton.smallActionButton(title: "Confirm my email instead", style: .secondary)
            confirm.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
            stack.addArrangedSubview(faceID)
            stack.addArrangedSubview(confirm)
            stack.setCustomSpacing(22, after: confirm)
            safetyEmail = email
        }

        if welcome.alreadySaved != true {
            let save = UIButton.primaryButton(title: "Save \(name) to my map")
            save.backgroundColor = Self.gold
            save.setTitleColor(Self.ink, for: .normal)
            save.layer.cornerRadius = 14
            save.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
            stack.addArrangedSubview(save)
        }
        if welcome.earnRate != nil {
            let rewards = UIButton.secondaryButton(title: "See my rewards")
            rewards.setTitleColor(.white, for: .normal)
            rewards.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
            rewards.layer.cornerRadius = 14
            rewards.addTarget(self, action: #selector(rewardsTapped), for: .touchUpInside)
            stack.addArrangedSubview(rewards)
        }
        let done = UIButton.smallActionButton(title: "Not now", style: .secondary)
        done.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        stack.addArrangedSubview(done)
    }

    private func rewardRow(_ offer: ClipWelcome.Offer, balance: Int) -> UIView {
        let title = Self.label(.systemFont(ofSize: 16, weight: .semibold))
        title.numberOfLines = 1
        title.text = offer.title
        let cost = Self.label(.systemFont(ofSize: 15, weight: .medium))
        let ready = balance >= offer.pointsCost
        cost.text = ready ? "Ready ✓" : "\(offer.pointsCost) pts"
        cost.textColor = ready ? Self.gold : UIColor.white.withAlphaComponent(0.8)
        cost.setContentHuggingPriority(.required, for: .horizontal)
        let line = UIStackView(arrangedSubviews: [title, cost])
        line.spacing = 8

        let bar = UIProgressView(progressViewStyle: .bar)
        bar.progressTintColor = Self.gold
        bar.trackTintColor = UIColor.white.withAlphaComponent(0.18)
        bar.progress = Float(min(1, Double(balance) / Double(max(offer.pointsCost, 1))))
        bar.layer.cornerRadius = 2
        bar.clipsToBounds = true
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true

        let row = UIStackView(arrangedSubviews: [line, bar])
        row.axis = .vertical
        row.spacing = 6
        row.isAccessibilityElement = true
        row.accessibilityLabel = ready ? "\(offer.title), ready" : "\(offer.title), \(offer.pointsCost) points"
        return row
    }

    // MARK: - Actions

    @objc private func saveTapped() {
        let onSave = onSave
        dismiss(animated: true) { onSave?() }
    }

    @objc private func rewardsTapped() {
        let onSeeRewards = onSeeRewards
        dismiss(animated: true) { onSeeRewards?() }
    }

    @objc private func faceIDTapped() {
        guard let email = safetyEmail else { return }
        AccountSafetyPrompt.setUpFaceID(email: email, from: self)
    }

    @objc private func confirmTapped() {
        guard let email = safetyEmail else { return }
        AccountSafetyPrompt.confirmEmail(email, from: self)
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    // MARK: - Look

    private static func serif(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func hook(_ first: String, _ second: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: first + "\n", attributes: [.font: serif(30), .foregroundColor: UIColor.white])
        text.append(NSAttributedString(string: second, attributes: [.font: serif(30), .foregroundColor: gold]))
        return text
    }

    private static func label(_ font: UIFont, color: UIColor = .white) -> UILabel {
        let label = UILabel()
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private static func heading(_ text: String) -> UILabel {
        let label = label(.systemFont(ofSize: 13, weight: .bold), color: gold)
        label.text = text
        return label
    }
}
