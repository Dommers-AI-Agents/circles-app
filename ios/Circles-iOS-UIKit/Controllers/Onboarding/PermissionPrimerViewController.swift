import UIKit

/// The "why we're asking" screen in front of a system permission prompt —
/// one layout for location and notifications so they can't drift. A
/// subclass supplies the copy and `requestPermission`, and calls `finish()`
/// once iOS has answered. Wes (2026-10-09): we want people to say yes to
/// both, so the reasons come first and "Not now" never nags.
class PermissionPrimerViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }

    struct Reason {
        let symbol: String
        let title: String
        let detail: String
    }

    // Supplied by subclasses
    var symbolName: String { "sparkles" }
    var headline: String { "" }
    var subheadline: String { "" }
    var reasons: [Reason] { [] }
    var footnote: String? { nil }
    var allowTitle: String { "Allow" }
    var skipTitle: String { "Not now" }

    /// Show iOS's prompt; call `finish()` when it's answered.
    func requestPermission() { finish() }

    var onCompletion: (() -> Void)?
    private var finished = false

    private lazy var allowButton = UIButton.primaryButton(title: allowTitle)
    private lazy var skipButton = UIButton.secondaryButton(title: skipTitle)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationController?.setNavigationBarHidden(true, animated: false)

        let icon = UIImageView(image: UIImage(systemName: symbolName))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 56, weight: .semibold)

        let title = UILabel()
        title.text = headline
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textAlignment = .center
        title.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = subheadline
        subtitle.font = .systemFont(ofSize: 17, weight: .medium)
        subtitle.textColor = Constants.Colors.secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(18, after: icon)
        stack.setCustomSpacing(26, after: subtitle)
        for reason in reasons { stack.addArrangedSubview(card(reason)) }
        if let footnote {
            let note = UILabel()
            note.text = footnote
            note.font = .systemFont(ofSize: 13)
            note.textColor = Constants.Colors.secondaryLabel
            note.textAlignment = .center
            note.numberOfLines = 0
            stack.setCustomSpacing(16, after: stack.arrangedSubviews.last ?? subtitle)
            stack.addArrangedSubview(note)
        }

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)
        view.addSubview(allowButton)
        view.addSubview(skipButton)
        allowButton.addTarget(self, action: #selector(allowTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)

        let content = scroll.contentLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: allowButton.topAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
            allowButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            allowButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            allowButton.bottomAnchor.constraint(equalTo: skipButton.topAnchor, constant: -10),
            skipButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            skipButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func card(_ reason: Reason) -> UIView {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12

        let icon = UIImageView(image: UIImage(systemName: reason.symbol))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        let title = UILabel()
        title.text = reason.title
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.numberOfLines = 0
        let detail = UILabel()
        detail.text = reason.detail
        detail.font = .systemFont(ofSize: 14)
        detail.textColor = Constants.Colors.secondaryLabel
        detail.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 3

        for v in [icon, text] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(v) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            text.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            text.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    @objc private func allowTapped() {
        allowButton.isEnabled = false
        skipButton.isEnabled = false
        requestPermission()
    }

    @objc private func skipTapped() {
        AnalyticsService.shared.logEvent("permission_primer_skipped", parameters: ["kind": String(describing: type(of: self))])
        finish()
    }

    /// Ends this step exactly once and moves the chain on.
    func finish() {
        guard !finished else { return }
        finished = true
        onCompletion?()
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
