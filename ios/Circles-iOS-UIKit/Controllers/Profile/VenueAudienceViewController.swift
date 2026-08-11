import UIKit

/// The people behind a dashboard number: who follows this venue, or who saved
/// it. Deliberately read-only — no message/connect buttons, so owner lists
/// can't become a DM harvesting tool. Owners broadcast via Announcements.
class VenueAudienceViewController: BaseViewController {

    enum Mode {
        case followers
        case savers

        var title: String {
            switch self {
            case .followers: return "Followers"
            case .savers: return "Saved By"
            }
        }
    }

    // MARK: - Properties

    private let venueId: String
    private let mode: Mode
    private var people: [VenueUserCard] = []
    private var headerText: String?

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        switch mode {
        case .followers: return "No followers yet. Your window QR and announcements are how people find you."
        case .savers: return "No visible saves yet."
        }
    }

    // MARK: - UI

    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = 64
        table.tableFooterView = UIView()
        return table
    }()

    // MARK: - Init

    init(venueId: String, mode: Mode) {
        self.venueId = venueId
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode.title
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(VenueAudienceCell.self, forCellReuseIdentifier: VenueAudienceCell.reuseId)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    // MARK: - Data

    override func loadData(completion: (() -> Void)? = nil) {
        switch mode {
        case .followers:
            RewardsService.shared.getVenueFollowers(venueId: venueId) { [weak self] result in
                DispatchQueue.main.async {
                    completion?()
                    guard let self = self else { return }
                    switch result {
                    case .success(let data):
                        self.people = data.followers
                        self.headerText = data.count == 1
                            ? "1 person follows this place"
                            : "\(data.count) people follow this place"
                        self.reload()
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        case .savers:
            RewardsService.shared.getVenueSavers(venueId: venueId) { [weak self] result in
                DispatchQueue.main.async {
                    completion?()
                    guard let self = self else { return }
                    switch result {
                    case .success(let data):
                        self.people = data.savers
                        // Be explicit that privacy hides some savers — an
                        // owner comparing this list to the tile count would
                        // otherwise read the gap as a bug
                        let hidden = data.totalCount - data.count
                        var text = data.totalCount == 1
                            ? "1 person saved this place"
                            : "\(data.totalCount) people saved this place"
                        if hidden > 0 {
                            text += " · \(hidden) kept their save private"
                        }
                        self.headerText = text
                        self.reload()
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func reload() {
        if let text = headerText {
            let label = UILabel()
            label.text = text
            label.font = UIFont.systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            label.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
            tableView.tableHeaderView = label
        }
        tableView.reloadData()
        if people.isEmpty {
            showEmptyState()
        } else {
            hideEmptyState()
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension VenueAudienceViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        people.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VenueAudienceCell.reuseId, for: indexPath) as! VenueAudienceCell
        cell.configure(with: people[indexPath.row], mode: mode)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Cell

class VenueAudienceCell: UITableViewCell {
    static let reuseId = "VenueAudienceCell"

    private let avatarView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.layer.cornerRadius = 20
        iv.clipsToBounds = true
        iv.contentMode = .scaleAspectFill
        iv.backgroundColor = Constants.Colors.secondaryBackground
        return iv
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.addSubview(avatarView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

            subtitleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.image = nil
    }

    func configure(with person: VenueUserCard, mode: VenueAudienceViewController.Mode) {
        nameLabel.text = person.displayName
        switch mode {
        case .followers:
            subtitleLabel.text = person.username.map { "@\($0)" }
        case .savers:
            if let savedAt = person.savedAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                subtitleLabel.text = "Saved \(formatter.string(from: savedAt))"
            } else {
                subtitleLabel.text = person.username.map { "@\($0)" }
            }
        }

        avatarView.image = UIImage(systemName: "person.circle.fill")
        avatarView.tintColor = Constants.Colors.secondaryLabel
        if let urlString = person.profilePicture, !urlString.isEmpty {
            ImageService.shared.loadProfileImage(for: person.id, from: urlString) { [weak self] image in
                DispatchQueue.main.async {
                    if let image = image { self?.avatarView.image = image }
                }
            }
        }
    }
}
