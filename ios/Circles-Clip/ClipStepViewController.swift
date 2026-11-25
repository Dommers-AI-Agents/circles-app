import UIKit

/// One optional step after the save (2026-11-24): the store's photo behind,
/// "1 of 3 · optional" with Skip on the same line, the serif hook, the
/// words, the step's own content, and a gold button at the bottom that the
/// keyboard and Apple's install banner both push up.
class ClipStepViewController: UIViewController {
    let flow: ClipOnboardingFlow
    let step: ClipOnboardingSummary.Step?

    let backdrop = ClipBackdropView(showsRoute: false)
    private let dim = UIView()
    private let brandMark = ClipTheme.brandMarkView(side: 40)
    private lazy var brandHeader = ClipTheme.brandHeader(mark: brandMark)
    let skipButton = ClipTheme.linkButton("Skip")
    let stepLabel = ClipTheme.label(.systemFont(ofSize: 13, weight: .bold), color: ClipTheme.gold)
    let hookLabel = ClipTheme.label(ClipTheme.serif(44))
    let detailLabel = ClipTheme.label(.systemFont(ofSize: 17), color: UIColor.white.withAlphaComponent(0.9))
    let errorLabel = ClipTheme.label(.systemFont(ofSize: 15, weight: .medium), color: UIColor(red: 1, green: 0.62, blue: 0.58, alpha: 1))
    let stack = UIStackView()
    let primaryButton: UIButton
    private var primaryBottom: NSLayoutConstraint?
    private var keyboardLift: CGFloat = 0
    private var bannerLift: CGFloat = 0
    private var advanced = false

    init(flow: ClipOnboardingFlow, step: ClipOnboardingSummary.Step?, primary: String) {
        self.flow = flow
        self.step = step
        self.primaryButton = ClipTheme.primaryButton(primary)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ClipTheme.ink
        navigationController?.setNavigationBarHidden(true, animated: false)
        view.addSubview(backdrop)
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dim.isUserInteractionEnabled = false
        dim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dim)
        view.addSubview(brandHeader)

        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        hookLabel.adjustsFontSizeToFitWidth = true
        hookLabel.minimumScaleFactor = 0.7
        [stepLabel, hookLabel, detailLabel, errorLabel].forEach(ClipTheme.lift)
        errorLabel.isHidden = true
        if let step {
            stepLabel.text = "\(flow.stepNumber(step)) OF \(flow.stepCount) · OPTIONAL"
        } else {
            stepLabel.text = "ALL SET"
            skipButton.isHidden = true
        }
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        skipButton.setContentHuggingPriority(.required, for: .horizontal)
        let stepRow = UIStackView(arrangedSubviews: [stepLabel, UIView(), skipButton])
        stepRow.axis = .horizontal
        stepRow.alignment = .center
        [stepRow, hookLabel, detailLabel].forEach { stack.addArrangedSubview($0) }
        stack.setCustomSpacing(4, after: stepRow)
        stack.setCustomSpacing(12, after: hookLabel)
        stack.setCustomSpacing(18, after: detailLabel)

        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        view.addSubview(primaryButton)

        let bottom = primaryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18)
        primaryBottom = bottom
        // With the keyboard up on a small phone the content can run out of room:
        // it may then slide under the header instead of breaking the layout
        let top = stack.topAnchor.constraint(greaterThanOrEqualTo: brandHeader.bottomAnchor, constant: 16)
        top.priority = UILayoutPriority(500)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dim.topAnchor.constraint(equalTo: view.topAnchor),
            dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            brandHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            brandHeader.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            brandHeader.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -26),
            top,
            stack.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -20),
            primaryButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 26),
            primaryButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -26),
            bottom
        ])
        Task { await backdrop.loadPhoto(from: flow.coverURL) }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    // MARK: - For the steps

    @objc func primaryTapped() {}

    @objc func skipTapped() {
        if let step { flow.skip(step) }
        advance()
    }

    /// On to the next screen, once
    func advance() {
        guard !advanced else { return }
        advanced = true
        view.endEditing(true)
        navigationController?.pushViewController(flow.screen(after: step), animated: true)
    }

    func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    func hideError() { errorLabel.isHidden = true }

    func setPrimaryTitle(_ title: String) {
        primaryButton.configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 18, weight: .semibold)]))
    }

    /// Gold when it can be tapped, glass while it can't (still readable)
    func setPrimaryEnabled(_ on: Bool) {
        primaryButton.isEnabled = on
        primaryButton.configuration?.baseBackgroundColor = on ? ClipTheme.gold : UIColor.white.withAlphaComponent(0.16)
        primaryButton.configuration?.baseForegroundColor = on ? ClipTheme.ink : .white
    }

    func setPrimaryBusy(_ busy: Bool) {
        primaryButton.configuration?.showsActivityIndicator = busy
        primaryButton.isEnabled = !busy
    }

    /// A gold caption like the success panel's
    func caption(_ text: String) -> UILabel {
        let label = ClipTheme.label(.systemFont(ofSize: 13, weight: .bold), color: ClipTheme.gold)
        label.text = text
        ClipTheme.lift(label)
        return label
    }

    /// Frosted panel holding a vertical stack
    func panel(_ content: UIStackView) -> UIView {
        let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        panel.layer.cornerRadius = 18
        panel.layer.masksToBounds = true
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -14),
            content.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -16)
        ])
        return panel
    }

    /// A gold pill at the top that fades: "3 places on your map"
    func toast(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = ClipTheme.ink
        label.backgroundColor = ClipTheme.gold
        label.textAlignment = .center
        label.layer.cornerRadius = 20
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 96),
            label.heightAnchor.constraint(equalToConstant: 40),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40)
        ])
        label.alpha = 0
        label.transform = CGAffineTransform(translationX: 0, y: -30).scaledBy(x: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5) {
            label.alpha = 1
            label.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.4, delay: 1.6, animations: {
                label.alpha = 0
                label.transform = CGAffineTransform(translationX: 0, y: -24)
            }) { _ in label.removeFromSuperview() }
        }
    }

    // MARK: - Lifting the content

    /// Keeps the button (and the content above it) clear of the keyboard
    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        keyboardLift = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY - view.safeAreaInsets.bottom)
        keyboardWillChange(up: keyboardLift > 0)
        // The header gives its room to the field while the keyboard is up
        UIView.animate(withDuration: 0.25) { self.brandHeader.alpha = self.keyboardLift > 0 ? 0 : 1 }
        applyLift()
    }

    /// The step's chance to make room while a field has focus (the hook
    /// and the words fold away on the favorites step)
    func keyboardWillChange(up: Bool) {}

    /// Apple's install banner slid up over the bottom: lift the button above it
    func lift(aboveBannerIn window: UIWindow, frame: CGRect) {
        let inView = view.convert(frame, from: window)
        bannerLift = max(0, view.bounds.maxY - view.safeAreaInsets.bottom - inView.minY) + 16
        applyLift()
    }

    private func applyLift() {
        primaryBottom?.constant = -18 - max(keyboardLift, bannerLift)
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }
}
