import UIKit

/// Step 3: people to follow (2026-11-24). The same list the app's first run
/// shows ("welcome" discovery: people who also saved the store, then people
/// near them, then the biggest maps — never contacts, which a clip can't
/// read). Follow is the app's POST users/:id/follow; a private profile
/// answers with a request.
final class ClipPeopleViewController: ClipStepViewController {
    private let rows = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = ClipTheme.label(.systemFont(ofSize: 14), color: UIColor.white.withAlphaComponent(0.75))
    private var people: [ClipPerson] = []
    private var followButtons: [String: UIButton] = [:]
    private var acted = Set<String>()

    private static let avatarColors: [UIColor] = [
        ClipTheme.pinRed, UIColor(red: 0.19, green: 0.51, blue: 0.81, alpha: 1), ClipTheme.pinGreen, ClipTheme.pinGold,
        UIColor(red: 0.55, green: 0.36, blue: 0.75, alpha: 1), UIColor(red: 0.18, green: 0.6, blue: 0.6, alpha: 1)
    ]

    init(flow: ClipOnboardingFlow) {
        super.init(flow: flow, step: .people, primary: "Continue")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        hookLabel.attributedText = ClipTheme.hookText("People who know", "the area.", size: 44)
        detailLabel.text = flow.store.map { "Locals with the most saved places near you, including \($0.name). Follow a few and their picks show up on your map." }
            ?? "Locals with the most saved places near you. Follow a few and their picks show up on your map."
        rows.axis = .vertical
        rows.spacing = 14
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.startAnimating()
        statusLabel.text = "Finding people near you…"
        ClipTheme.lift(statusLabel)
        let box = panel(rows)
        box.isHidden = true
        [spinner, statusLabel, box, errorLabel].forEach { stack.addArrangedSubview($0) }
        ClipTheme.animateIn([stepLabel, hookLabel, detailLabel, primaryButton])
        load(box: box)
    }

    private func load(box: UIView) {
        Task { @MainActor in
            do {
                people = try await ClipAPIClient.shared.discoverPeople(limit: 6, bearer: flow.session.token)
            } catch {
                people = []
            }
            spinner.stopAnimating()
            if people.isEmpty {
                statusLabel.text = "No one mapping your area yet. You'll be the first."
            } else {
                statusLabel.isHidden = true
                for (index, person) in people.enumerated() {
                    rows.addArrangedSubview(row(person, index: index))
                }
                box.isHidden = false
                ClipTheme.animateIn([box], baseDelay: 0)
            }
            #if DEBUG
            ClipAutopilot.shared?.ready(self)
            #endif
        }
    }

    private func row(_ person: ClipPerson, index: Int) -> UIView {
        let avatar = UILabel()
        avatar.text = person.initials
        avatar.font = .systemFont(ofSize: 15, weight: .bold)
        avatar.textColor = .white
        avatar.textAlignment = .center
        avatar.backgroundColor = Self.avatarColors[index % Self.avatarColors.count]
        avatar.layer.cornerRadius = 21
        avatar.layer.masksToBounds = true
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.widthAnchor.constraint(equalToConstant: 42).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 42).isActive = true
        let photo = UIImageView()
        photo.contentMode = .scaleAspectFill
        photo.layer.cornerRadius = 21
        photo.layer.masksToBounds = true
        photo.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(photo)
        NSLayoutConstraint.activate([
            photo.topAnchor.constraint(equalTo: avatar.topAnchor), photo.bottomAnchor.constraint(equalTo: avatar.bottomAnchor),
            photo.leadingAnchor.constraint(equalTo: avatar.leadingAnchor), photo.trailingAnchor.constraint(equalTo: avatar.trailingAnchor)
        ])
        if let url = person.profilePicture.flatMap(URL.init(string:)) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                    await MainActor.run { photo.image = image }
                }
            }
        }

        let name = ClipTheme.label(.systemFont(ofSize: 16, weight: .semibold), lines: 1)
        name.text = person.displayName
        let sub = ClipTheme.label(.systemFont(ofSize: 13), color: UIColor.white.withAlphaComponent(0.75), lines: 2)
        sub.text = person.detailLine
        let words = UIStackView(arrangedSubviews: [name, sub])
        words.axis = .vertical
        words.spacing = 2

        let follow = Self.followButton(title: person.isFollowing == true ? "Following ✓" : "Follow", on: person.isFollowing == true)
        follow.isEnabled = person.isFollowing != true
        follow.addAction(UIAction { [weak self] _ in self?.follow(person) }, for: .touchUpInside)
        followButtons[person.id] = follow

        let row = UIStackView(arrangedSubviews: [avatar, words, follow])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    private static func followButton(title: String, on: Bool) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.background.strokeColor = UIColor.white.withAlphaComponent(0.4)
        config.background.strokeWidth = 1
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        let button = UIButton(configuration: config)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        set(button, title: title, on: on)
        return button
    }

    private static func set(_ button: UIButton, title: String, on: Bool) {
        button.configuration?.baseBackgroundColor = on ? ClipTheme.gold : UIColor.white.withAlphaComponent(0.18)
        button.configuration?.baseForegroundColor = on ? ClipTheme.ink : .white
        button.configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]))
    }

    private func follow(_ person: ClipPerson) {
        guard !acted.contains(person.id), let button = followButtons[person.id] else { return }
        acted.insert(person.id)
        button.isEnabled = false
        button.configuration?.showsActivityIndicator = true
        hideError()
        Task { @MainActor in
            defer { button.configuration?.showsActivityIndicator = false }
            do {
                let response = try await ClipAPIClient.shared.follow(userId: person.id, bearer: flow.session.token)
                let requested = response.requested == true
                Self.set(button, title: requested ? "Requested" : "Following ✓", on: true)
                flow.record { s in
                    if requested { s.requested += 1 } else { s.followed += 1 }
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } catch {
                acted.remove(person.id)
                button.isEnabled = true
                showError(error.localizedDescription)
            }
        }
    }

    override func primaryTapped() {
        flow.complete(.people)
        advance()
    }
}
