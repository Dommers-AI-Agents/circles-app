import UIKit

class PlaceSaversViewController: BaseViewController {

    // MARK: - Properties
    var placeId: String?
    var placeName: String?

    private var sections: [(title: String?, users: [User])] = []

    // MARK: - UI Elements
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.backgroundColor = Constants.Colors.background
        return tableView
    }()

    // MARK: - Configuration
    override var emptyStateMessage: String? { "No savers to show yet\n\nWhen people save this place to their circles, they'll appear here." }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - Setup
    private func setupUI() {
        title = "Saved by"

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PlaceSaverUserCell.self, forCellReuseIdentifier: "PlaceSaverUserCell")
    }

    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)?) {
        guard let placeId = placeId else {
            completion?()
            return
        }

        PlaceService.shared.fetchPlaceSavers(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.buildSections(from: response.savers)
                    self?.tableView.reloadData()
                    self?.updateEmptyState()
                case .failure(let error):
                    self?.showError(error)
                    self?.updateEmptyState()
                }
                completion?()
            }
        }
    }

    private func buildSections(from users: [User]) {
        let inNetwork = users.filter { $0.connectionStatus == "accepted" || $0.connectionStatus == "self" }
        let others = users.filter { $0.connectionStatus != "accepted" && $0.connectionStatus != "self" }

        if inNetwork.isEmpty || others.isEmpty {
            sections = [(title: nil, users: inNetwork + others)]
        } else {
            sections = [
                (title: "In your network", users: inNetwork),
                (title: "Others who saved this place", users: others)
            ]
        }
    }

    private func updateEmptyState() {
        if sections.allSatisfy({ $0.users.isEmpty }) {
            showEmptyState()
        } else {
            hideEmptyState()
        }
    }

    // MARK: - Actions
    private func sendConnectionRequest(to user: User, at indexPath: IndexPath) {
        NetworkManager.shared.sendConnectionRequest(to: user.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    guard let self = self,
                          indexPath.section < self.sections.count,
                          indexPath.row < self.sections[indexPath.section].users.count else { return }
                    self.sections[indexPath.section].users[indexPath.row] = user.copy(connectionStatus: "pending")
                    self.tableView.reloadRows(at: [indexPath], with: .none)
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource
extension PlaceSaversViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].users.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceSaverUserCell", for: indexPath) as! PlaceSaverUserCell
        let user = sections[indexPath.section].users[indexPath.row]
        cell.configure(with: user)
        cell.onConnectTapped = { [weak self] in
            self?.sendConnectionRequest(to: user, at: indexPath)
        }
        return cell
    }
}

// MARK: - UITableViewDelegate
extension PlaceSaversViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = sections[indexPath.section].users[indexPath.row]

        let profileVC = ProfileViewController(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}

// MARK: - Place Saver User Cell
class PlaceSaverUserCell: UITableViewCell {

    var onConnectTapped: (() -> Void)?

    // MARK: - UI Elements
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.layer.cornerRadius = 25
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let bioLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var connectButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Connect", style: .primary)
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        button.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup
    private func setupUI() {
        backgroundColor = Constants.Colors.background
        selectionStyle = .default

        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(bioLabel)
        contentView.addSubview(connectButton)

        NSLayoutConstraint.activate([
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 50),
            profileImageView.heightAnchor.constraint(equalToConstant: 50),

            connectButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            connectButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            nameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor, constant: 5),
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: connectButton.leadingAnchor, constant: -12),

            bioLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            bioLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            bioLabel.trailingAnchor.constraint(lessThanOrEqualTo: connectButton.leadingAnchor, constant: -12)
        ])
    }

    // MARK: - Configuration
    func configure(with user: User) {
        nameLabel.text = user.connectionStatus == "self" ? "You" : user.displayName

        if let bio = user.bio, !bio.isEmpty {
            bioLabel.text = bio
        } else {
            bioLabel.text = "Circles user"
        }

        configureConnectButton(for: user.connectionStatus)

        if let profilePicture = user.profilePicture {
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.primary
        }
    }

    private func configureConnectButton(for connectionStatus: String?) {
        connectButton.isHidden = false
        connectButton.isEnabled = false
        connectButton.layer.borderWidth = 0

        switch connectionStatus {
        case "self":
            connectButton.isHidden = true
        case "accepted", "connected":
            connectButton.setTitle("Connected", for: .normal)
            connectButton.setTitleColor(.systemGray, for: .normal)
            connectButton.backgroundColor = .systemGray5
        case "pending":
            connectButton.setTitle("Pending", for: .normal)
            connectButton.setTitleColor(.systemGray, for: .normal)
            connectButton.backgroundColor = .systemGray5
        default:
            connectButton.isEnabled = true
            connectButton.setTitle("Connect", for: .normal)
            connectButton.setTitleColor(.white, for: .normal)
            connectButton.backgroundColor = Constants.Colors.primary
        }
    }

    @objc private func connectTapped() {
        onConnectTapped?()
    }

    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.image = nil
        nameLabel.text = nil
        bioLabel.text = nil
        onConnectTapped = nil
    }
}
