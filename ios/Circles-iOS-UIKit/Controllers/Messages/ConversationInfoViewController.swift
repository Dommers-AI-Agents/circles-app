import UIKit

/// The ⓘ in a one-on-one chat (2026-10-30; it was an empty stub): the other
/// person (tap for their profile), muting the chat's notifications, and the
/// places, circles and locations shared in it, newest first.
final class ConversationInfoViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let conversation: Conversation
    private let shared: [MessageShareCard]
    private var notificationsOn: Bool
    /// Open a share card (the chat does it, so it pushes on the chat's stack)
    var onOpenShare: ((MessageShareCard) -> Void)?
    var onOpenProfile: ((String) -> Void)?
    /// The new setting, after the server took it
    var onNotificationsChanged: ((Bool) -> Void)?

    private enum Section: Int, CaseIterable { case person, notifications, shared }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(conversation: Conversation, shared: [MessageShareCard]) {
        self.conversation = conversation
        self.shared = shared
        self.notificationsOn = conversation.notificationsEnabled
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Chat Info"
        view.backgroundColor = .systemGroupedBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private var otherPerson: User? { conversation.participantDetails?.first }

    @objc private func notificationsSwitched(_ sender: UISwitch) {
        let enabled = sender.isOn
        sender.isEnabled = false
        MessagingManager.shared.toggleNotifications(for: conversation.id, enabled: enabled) { [weak self] result in
            DispatchQueue.main.async {
                sender.isEnabled = true
                guard let self else { return }
                switch result {
                case .success:
                    self.notificationsOn = enabled
                    self.onNotificationsChanged?(enabled)
                case .failure(let error):
                    sender.setOn(!enabled, animated: true)
                    self.showError(error)
                }
            }
        }
    }
}

extension ConversationInfoViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .person, .notifications: return 1
        case .shared: return max(shared.count, 1)
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section) == .shared ? "Shared in this chat" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        var config = UIListContentConfiguration.subtitleCell()
        switch Section(rawValue: indexPath.section)! {
        case .person:
            config.text = conversation.displayName
            config.secondaryText = "View profile"
            config.textProperties.font = .systemFont(ofSize: 18, weight: .semibold)
            config.image = AvatarPlaceholder.image(name: conversation.displayName, seed: otherPerson?.id ?? conversation.id, diameter: 44)
            config.imageProperties.cornerRadius = 22
            config.imageProperties.maximumSize = CGSize(width: 44, height: 44)
            cell.accessoryType = otherPerson == nil ? .none : .disclosureIndicator
            if let url = conversation.displayAvatar, !url.isEmpty {
                ImageService.shared.loadImage(from: url) { [weak tableView] image in
                    DispatchQueue.main.async {
                        guard let image, let cell = tableView?.cellForRow(at: indexPath),
                              var updated = cell.contentConfiguration as? UIListContentConfiguration else { return }
                        updated.image = image
                        cell.contentConfiguration = updated
                    }
                }
            }
        case .notifications:
            config = UIListContentConfiguration.cell()
            config.text = "Notifications"
            config.image = UIImage(systemName: "bell")
            let toggle = UISwitch()
            toggle.isOn = notificationsOn
            toggle.addTarget(self, action: #selector(notificationsSwitched(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .shared:
            guard indexPath.row < shared.count else {
                config = UIListContentConfiguration.cell()
                config.text = "Places, circles and locations you share here show up in this list."
                config.textProperties.color = .secondaryLabel
                config.textProperties.font = .systemFont(ofSize: 14)
                cell.selectionStyle = .none
                break
            }
            let card = shared[indexPath.row]
            config.text = "\(card.symbol) \(card.title)"
            config.secondaryText = card.subtitle
            config.secondaryTextProperties.color = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .person:
            if let id = otherPerson?.id { onOpenProfile?(id) }
        case .notifications:
            break
        case .shared:
            guard indexPath.row < shared.count else { return }
            onOpenShare?(shared[indexPath.row])
        }
    }
}
