import UIKit

protocol MessagesStarterViewDelegate: AnyObject {
    func messagesStarterDidTapSuggestions(_ view: MessagesStarterView)
    func messagesStarter(_ view: MessagesStarterView, didSelectUser user: User)
    func messagesStarter(_ view: MessagesStarterView, didTapConnect user: User, button: UIButton)
    func messagesStarterDidTapInvite(_ view: MessagesStarterView)
    func messagesStarterDidTapFindPeople(_ view: MessagesStarterView)
}

/// What the Messages tab shows before there are any conversations (Wes,
/// 2026-10-17: an empty tab is wasted space for a new user). Not a dead end:
/// the places people sent them, people they may know with a Connect button
/// (connections are who you can message), and a way to invite a friend.
/// The owner feeds it data; this view only lays it out.
final class MessagesStarterView: UIView {

    weak var delegate: MessagesStarterViewDelegate?

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let iconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right.fill"))
        view.tintColor = Constants.Colors.primary
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private let suggestionsSection = UIStackView()
    private let peopleSection = UIStackView()

    private lazy var inviteButton = UIButton.primaryButton(title: "Invite a Friend")
    private lazy var findPeopleButton = UIButton.secondaryButton(title: "Find People You Know")

    private var suggestions: [Suggestion] = []
    private var people: [User] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        addSubview(scrollView)
        scrollView.addSubview(stack)

        for section in [suggestionsSection, peopleSection] {
            section.axis = .vertical
            section.spacing = 8
            section.isHidden = true
        }

        let header = UIStackView(arrangedSubviews: [iconView, titleLabel, bodyLabel])
        header.axis = .vertical
        header.alignment = .leading
        header.spacing = 8
        header.setCustomSpacing(14, after: iconView)

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(suggestionsSection)
        stack.addArrangedSubview(peopleSection)
        stack.addArrangedSubview(inviteButton)
        stack.addArrangedSubview(findPeopleButton)
        stack.setCustomSpacing(24, after: header)
        stack.setCustomSpacing(24, after: suggestionsSection)
        stack.setCustomSpacing(24, after: peopleSection)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            // Room under the last button for the floating compose button
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -96),

            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44)
        ])

        inviteButton.addTarget(self, action: #selector(inviteTapped), for: .touchUpInside)
        findPeopleButton.addTarget(self, action: #selector(findPeopleTapped), for: .touchUpInside)
        setHasConnections(false)
    }

    // MARK: - Data

    /// Connected people can be messaged right away; someone with no
    /// connections yet has to connect first.
    func setHasConnections(_ hasConnections: Bool) {
        if hasConnections {
            titleLabel.text = "Start a conversation"
            bodyLabel.text = "Tap the pencil to message a connection or send them a place. Group chats are great for planning a night out."
        } else {
            titleLabel.text = "Message the people you know"
            bodyLabel.text = "Once you're connected with someone, you can message them, send each other places and plan in group chats."
        }
    }

    /// The places people sent them, newest first (a new user's is Wes's
    /// welcome pick). Up to two rows; the inbox has the rest.
    func setSuggestions(_ suggestions: [Suggestion]) {
        self.suggestions = Array(suggestions.sorted { $0.createdAt > $1.createdAt }.prefix(2))
        rebuild(suggestionsSection,
                title: "Sent to you",
                rows: self.suggestions.enumerated().map { suggestionRow($0.element, index: $0.offset) })
    }

    /// People they may know, up to five, each with a Connect button.
    func setPeople(_ people: [User]) {
        self.people = Array(people.prefix(5))
        rebuild(peopleSection,
                title: "People you may know",
                rows: self.people.enumerated().map { personRow($0.element, index: $0.offset) })
    }

    private func rebuild(_ section: UIStackView, title: String, rows: [UIView]) {
        section.arrangedSubviews.forEach { $0.removeFromSuperview() }
        section.isHidden = rows.isEmpty
        guard !rows.isEmpty else { return }
        let header = UILabel()
        header.text = title
        header.font = .systemFont(ofSize: 17, weight: .semibold)
        header.textColor = Constants.Colors.label
        section.addArrangedSubview(header)
        rows.forEach { section.addArrangedSubview($0) }
    }

    // MARK: - Rows

    private func card() -> UIControl {
        let control = UIControl()
        control.backgroundColor = Constants.Colors.secondaryBackground
        control.layer.cornerRadius = 14
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }

    private func avatar(size: CGFloat) -> UIImageView {
        let view = UIImageView(image: UIImage(systemName: "person.crop.circle.fill"))
        view.tintColor = .systemGray3
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = size / 2
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: size),
            view.heightAnchor.constraint(equalToConstant: size)
        ])
        return view
    }

    private func textStack(_ title: String, _ subtitle: String?) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = Constants.Colors.label
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = Constants.Colors.secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isHidden = (subtitle ?? "").isEmpty
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        return stack
    }

    private func row(in control: UIControl, leading: UIView, text: UIStackView, trailing: UIView) {
        leading.isUserInteractionEnabled = false
        let content = UIStackView(arrangedSubviews: [leading, text, trailing])
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: control.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -12),
            content.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -12)
        ])
    }

    private func suggestionRow(_ suggestion: Suggestion, index: Int) -> UIView {
        let control = card()
        let image = avatar(size: 48)
        image.layer.cornerRadius = 10
        image.image = UIImage(systemName: "mappin.circle.fill")
        image.tintColor = Constants.Colors.primary
        let photo = suggestion.imageUrl ?? suggestion.placeDetails?.photos?.first
        if let photo, !photo.isEmpty {
            ImageService.shared.loadImage(from: photo) { loaded in
                DispatchQueue.main.async { if let loaded { image.image = loaded } }
            }
        }
        let placeName = suggestion.placeDetails?.name ?? "A place for you"
        let text = textStack(placeName, "From \(suggestion.displayAuthorName) · \(suggestion.timeAgo)")
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        row(in: control, leading: image, text: text, trailing: chevron)
        control.addTarget(self, action: #selector(suggestionTapped), for: .touchUpInside)
        return control
    }

    private func personRow(_ user: User, index: Int) -> UIView {
        let control = card()
        control.tag = index
        let image = avatar(size: 48)
        ImageService.shared.loadProfileImage(for: user.id, from: user.profilePicture) { loaded in
            DispatchQueue.main.async { if let loaded { image.image = loaded } }
        }
        let text = textStack(user.displayName, Self.reason(for: user))
        let requested = user.connectionStatus == "pending"
        let connect = UIButton.smallActionButton(title: requested ? "Requested" : "Connect",
                                                 style: requested ? .following : .primary)
        connect.isEnabled = !requested
        connect.tag = index
        connect.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        connect.setContentHuggingPriority(.required, for: .horizontal)
        connect.setContentCompressionResistancePriority(.required, for: .horizontal)
        connect.addTarget(self, action: #selector(connectTapped(_:)), for: .touchUpInside)
        row(in: control, leading: image, text: text, trailing: connect)
        control.addTarget(self, action: #selector(personTapped(_:)), for: .touchUpInside)
        return control
    }

    /// Why we think they know them, in the server's words when it gave one.
    private static func reason(for user: User) -> String? {
        if let reason = user.suggestionReason, !reason.isEmpty { return reason }
        if let mutual = user.mutualConnectionsCount, mutual > 0 {
            return mutual == 1 ? "1 mutual connection" : "\(mutual) mutual connections"
        }
        if let places = user.placesCount, places > 0 {
            return places == 1 ? "1 favorite place" : "\(places) favorite places"
        }
        return nil
    }

    // MARK: - Actions

    @objc private func suggestionTapped() {
        delegate?.messagesStarterDidTapSuggestions(self)
    }

    @objc private func personTapped(_ sender: UIControl) {
        guard people.indices.contains(sender.tag) else { return }
        delegate?.messagesStarter(self, didSelectUser: people[sender.tag])
    }

    @objc private func connectTapped(_ sender: UIButton) {
        guard people.indices.contains(sender.tag) else { return }
        delegate?.messagesStarter(self, didTapConnect: people[sender.tag], button: sender)
    }

    @objc private func inviteTapped() {
        delegate?.messagesStarterDidTapInvite(self)
    }

    @objc private func findPeopleTapped() {
        delegate?.messagesStarterDidTapFindPeople(self)
    }
}
