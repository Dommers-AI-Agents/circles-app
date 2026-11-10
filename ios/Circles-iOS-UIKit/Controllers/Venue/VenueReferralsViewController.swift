import UIKit

/// Manage Store → Bring a friend (Business, 2026-11-09): on/off, the points
/// for the inviter and the friend, and how many friends were brought in.
final class VenueReferralsViewController: BaseViewController {

    private let venueId: String
    private var settings: StoreReferralSettings
    private var stats: StoreReferralStats?
    var onChanged: ((StoreReferralSettings) -> Void)?

    override var enablesPullToRefresh: Bool { true }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    private lazy var enabledSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(enabledChanged), for: .valueChanged)
        return toggle
    }()

    init(venueId: String, settings: StoreReferralSettings?) {
        self.venueId = venueId
        self.settings = settings ?? .off
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bring a friend"
        view.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func setupRefreshControl() { tableView.refreshControl = refreshControl }

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.fetchReferrals(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let data):
                    self.settings = data.settings
                    self.stats = data.stats
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    private func save(_ next: StoreReferralSettings) {
        let previous = settings
        settings = next
        tableView.reloadData()
        RewardsService.shared.updateReferrals(venueId: venueId, settings: next) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let saved):
                    self.settings = saved
                    self.tableView.reloadData()
                    self.onChanged?(saved)
                case .failure(let error):
                    self.settings = previous
                    self.tableView.reloadData()
                    self.showError(error)
                }
            }
        }
    }

    @objc private func enabledChanged() {
        var next = settings
        next.enabled = enabledSwitch.isOn
        save(next)
    }

    private func editPoints(referrer: Bool) {
        let current = referrer ? settings.referrerPoints : settings.friendPoints
        AlertPresenter.showTextInput(title: referrer ? "Points for the inviter" : "Points for the new customer",
                                     message: "Paid when the friend's first purchase is scanned.",
                                     placeholder: "\(current)", initialText: "\(current)", keyboardType: .numberPad,
                                     confirmTitle: "Save", from: self) { [weak self] text in
            guard let self, let text, let points = Int(text.trimmingCharacters(in: .whitespaces)), points >= 0 else { return }
            var next = self.settings
            if referrer { next.referrerPoints = points } else { next.friendPoints = points }
            self.save(next)
        }
    }
}

extension VenueReferralsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 : 1 }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Bring a friend" : "Results" }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 0 ? StoreReferralCopy.explanation : nil }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        if indexPath.section == 1 {
            config.text = StoreReferralCopy.statsLine(stats)
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        } else if indexPath.row == 0 {
            config.text = "On"
            enabledSwitch.isOn = settings.enabled
            cell.accessoryView = enabledSwitch
            cell.selectionStyle = .none
        } else {
            let referrer = indexPath.row == 1
            config.text = referrer ? "The inviter gets" : "The new customer gets"
            config.secondaryText = StoreReferralCopy.pointsLine(referrer ? settings.referrerPoints : settings.friendPoints)
            config.secondaryTextProperties.color = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0, indexPath.row > 0 else { return }
        editPoints(referrer: indexPath.row == 1)
    }
}
