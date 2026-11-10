import UIKit

/// The host's waitlist (Business, 2026-11-09): the setting (on/off and the
/// quoted wait), then the line oldest first — Notify (pushes the guest),
/// Seated, Remove. Refreshed every 20 s and whenever a waitlist push lands.
final class VenueWaitlistViewController: BaseViewController {

    override var enablesPullToRefresh: Bool { true }
    override var reloadsDataOnAppear: Bool { true }

    private let venueId: String
    private var settings: StoreWaitlist
    private var line: [WaitlistEntry] = []
    private var poller: Timer?
    private var observer: NSObjectProtocol?
    /// The setting and how many wait, for Manage Store's row
    var onChanged: ((StoreWaitlist, Int) -> Void)?

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 60
        return table
    }()
    private lazy var enabledSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(enabledChanged), for: .valueChanged)
        return toggle
    }()

    init(venueId: String, settings: StoreWaitlist?) {
        self.venueId = venueId
        self.settings = settings ?? StoreWaitlist()
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Waitlist"
        view.backgroundColor = .systemGroupedBackground
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        tableView.refreshControl = refreshControl
        observer = NotificationCenter.default.addObserver(forName: .waitlistChanged, object: nil, queue: .main) { [weak self] _ in self?.loadData() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        poller?.invalidate()
        poller = nil
    }

    override func loadData(completion: (() -> Void)? = nil) {
        WaitlistService.shared.storeLine(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { completion?(); return }
                switch result {
                case .success(let data):
                    self.settings = data.settings
                    self.line = data.line
                    self.enabledSwitch.isOn = data.settings.enabled
                    self.tableView.reloadData()
                    self.onChanged?(self.settings, self.line.count)
                case .failure(let error):
                    self.showError(error.serverMessage ?? "Couldn\u{2019}t load the waitlist.")
                }
                self.poller?.invalidate()
                self.poller = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                    if self?.view.window != nil { self?.loadData() }
                }
                completion?()
            }
        }
    }

    // MARK: - Settings

    private func save(_ next: StoreWaitlist) {
        let previous = settings
        settings = next
        tableView.reloadData()
        WaitlistService.shared.saveSettings(venueId: venueId, settings: next) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let saved):
                    self.settings = saved
                    self.enabledSwitch.isOn = saved.enabled
                    self.tableView.reloadData()
                    self.onChanged?(saved, self.line.count)
                case .failure(let error):
                    self.settings = previous
                    self.enabledSwitch.isOn = previous.enabled
                    self.tableView.reloadData()
                    self.showError(error.serverMessage ?? "Couldn\u{2019}t save.")
                }
            }
        }
    }

    @objc private func enabledChanged() {
        var next = settings
        next.enabled = enabledSwitch.isOn
        save(next)
    }

    private func pickQuote(from sourceView: UIView) {
        let actions = WaitlistCopy.quoteOptions.map { minutes in
            (title: "\(minutes) minutes", style: UIAlertAction.Style.default, handler: { [weak self] in
                guard let self else { return }
                var next = self.settings
                next.quoteMinutes = minutes
                self.save(next)
            })
        }
        AlertPresenter.showActionSheet(title: "Quoted wait per party ahead", actions: actions, from: self, sourceView: sourceView)
    }

    // MARK: - The line

    private func act(on entry: WaitlistEntry, sourceView: UIView) {
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = []
        if !entry.isCalled {
            actions.append((title: "Notify — table's ready", style: .default, handler: { [weak self] in self?.perform(.notify, on: entry) }))
        }
        actions.append((title: "Seated", style: .default, handler: { [weak self] in self?.perform(.seat, on: entry) }))
        actions.append((title: "Remove from the line", style: .destructive, handler: { [weak self] in self?.perform(.remove, on: entry) }))
        AlertPresenter.showActionSheet(title: WaitlistCopy.hostRow(entry), actions: actions, from: self, sourceView: sourceView)
    }

    private func perform(_ action: WaitlistService.HostAction, on entry: WaitlistEntry) {
        WaitlistService.shared.act(venueId: venueId, entryId: entry.entryId, action: action) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.loadData()
                case .failure(let error):
                    self.showError(error.serverMessage ?? "Couldn\u{2019}t update the line.")
                    self.loadData()
                }
            }
        }
    }
}

extension VenueWaitlistViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 2 : max(line.count, 1)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Waitlist" : WaitlistCopy.lineHeader(count: line.count)
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? WaitlistCopy.settingsFooter(enabled: settings.enabled, quoteMinutes: settings.quoteMinutes) : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                config.text = "Taking a waitlist"
                enabledSwitch.isOn = settings.enabled
                cell.accessoryView = enabledSwitch
                cell.selectionStyle = .none
            } else {
                config.text = "Quoted wait"
                config.secondaryText = "\(settings.quoteMinutes) minutes per party ahead"
                config.secondaryTextProperties.color = .secondaryLabel
                cell.accessoryType = .disclosureIndicator
            }
        } else if line.isEmpty {
            config.text = settings.enabled ? "The line is empty" : "Turn the waitlist on to take parties"
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        } else {
            let entry = line[indexPath.row]
            config.text = "#\(entry.position ?? indexPath.row + 1)  \(WaitlistCopy.hostRow(entry))"
            config.textProperties.color = entry.isCalled ? Constants.Colors.primary : Constants.Colors.label
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        if indexPath.section == 0 {
            if indexPath.row == 1 { pickQuote(from: cell) }
            return
        }
        guard line.indices.contains(indexPath.row) else { return }
        act(on: line[indexPath.row], sourceView: cell)
    }
}
