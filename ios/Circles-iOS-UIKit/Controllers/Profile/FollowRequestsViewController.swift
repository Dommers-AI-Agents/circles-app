import UIKit

/// Settings → Privacy → Follow Requests, and where a `follow_request` push
/// lands: people asking to follow a private profile (Wes, 2026-11-02).
/// Accept lets them follow; Decline removes the ask without telling them.
final class FollowRequestsViewController: BaseTableViewController {

    private var requests: [FollowRequest] = []

    override var emptyStateMessage: String? { "No one is waiting.\nWhen your profile is private, people who ask to follow you show up here." }
    override var reloadsDataOnAppear: Bool { true }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Follow Requests"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(FollowRequestCell.self, forCellReuseIdentifier: FollowRequestCell.reuseId)
    }

    override func loadData(completion: (() -> Void)? = nil) {
        FollowRequestService.shared.fetchRequests { [weak self] result in
            guard let self = self else { completion?(); return }
            switch result {
            case .success(let requests):
                self.requests = requests
                self.tableView.reloadData()
                requests.isEmpty ? self.showEmptyState() : self.hideEmptyState()
            case .failure(let error):
                // A failed load keeps whatever was showing
                AlertPresenter.showError(error, from: self)
            }
            completion?()
        }
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        requests.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: FollowRequestCell.reuseId, for: indexPath) as! FollowRequestCell
        let request = requests[indexPath.row]
        cell.configure(with: request.user)
        cell.onAccept = { [weak self] in self?.answer(request, accept: true) }
        cell.onDecline = { [weak self] in self?.answer(request, accept: false) }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(ProfileViewController(user: requests[indexPath.row].user), animated: true)
    }

    private func answer(_ request: FollowRequest, accept: Bool) {
        let done: (Result<Void, APIError>) -> Void = { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                if let index = self.requests.firstIndex(where: { $0.id == request.id }) {
                    self.requests.remove(at: index)
                    self.tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
                }
                if self.requests.isEmpty { self.showEmptyState() }
                if accept { self.showSuccess("\(request.user.displayName) now follows you.") }
            case .failure(let error):
                AlertPresenter.showError(error, from: self)
            }
        }
        if accept {
            FollowRequestService.shared.accept(request.requesterId, completion: done)
        } else {
            FollowRequestService.shared.decline(request.requesterId, completion: done)
        }
    }
}

/// One asker: avatar, name, Accept and Decline.
private final class FollowRequestCell: UITableViewCell {
    static let reuseId = "FollowRequestCell"

    var onAccept: (() -> Void)?
    var onDecline: (() -> Void)?

    private let avatarView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 22
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var acceptButton = UIButton.smallActionButton(title: "Accept", style: .primary)
    private lazy var declineButton = UIButton.smallActionButton(title: "Decline", style: .secondary)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let buttons = UIStackView(arrangedSubviews: [acceptButton, declineButton])
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(buttons)
        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -8),
            buttons.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            buttons.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttons.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with user: User) {
        nameLabel.text = user.displayName
        avatarView.setUserAvatar(for: user, diameter: 44)
        accessibilityLabel = "\(user.displayName) asked to follow you"
    }

    @objc private func acceptTapped() { onAccept?() }
    @objc private func declineTapped() { onDecline?() }
}
