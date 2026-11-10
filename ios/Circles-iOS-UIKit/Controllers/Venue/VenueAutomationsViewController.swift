import UIKit

/// Manage Store → Bring them back (Wes, 2026-11-09; FavCircles Business):
/// the store's automatic nudges — win-back, birthday treat, almost there —
/// each a switch with its own bonus, and how each has done. Saved on every
/// change; the server plans and sends them daily (services/storeAutomations).
final class VenueAutomationsViewController: BaseViewController {

    private let venueId: String
    private var settings: StoreAutomations
    private var stats: StoreAutomationStats?
    /// The settings, for Manage Store's row
    var onChanged: ((StoreAutomations) -> Void)?

    override var enablesPullToRefresh: Bool { true }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 56
        return table
    }()

    private enum Row { case toggle, days, bonus, stats }

    init(venueId: String, settings: StoreAutomations?) {
        self.venueId = venueId
        self.settings = settings ?? .off
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bring them back"
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

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.fetchAutomations(venueId: venueId) { [weak self] result in
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

    // MARK: - Saving

    private func save(_ next: StoreAutomations) {
        let previous = settings
        settings = next
        tableView.reloadData()
        RewardsService.shared.updateAutomations(venueId: venueId, settings: next) { [weak self] result in
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

    @objc private func toggled(_ sender: UISwitch) {
        var next = settings
        switch StoreAutomationsCopy.Kind.allCases[sender.tag] {
        case .winBack: next.winBack.enabled = sender.isOn
        case .birthday: next.birthday.enabled = sender.isOn
        case .almostThere: next.almostThere.enabled = sender.isOn
        }
        save(next)
    }

    private func pickDays(from sourceView: UIView) {
        let actions = StoreAutomationsCopy.winBackDays.map { days in
            (title: StoreAutomationsCopy.daysTitle(days), style: UIAlertAction.Style.default, handler: { [weak self] in
                guard let self else { return }
                var next = self.settings
                next.winBack.days = days
                self.save(next)
            })
        }
        AlertPresenter.showActionSheet(title: "Nudge after how long without a purchase?", actions: actions, from: self, sourceView: sourceView)
    }

    private func editBonus(_ kind: StoreAutomationsCopy.Kind) {
        let current = kind == .winBack ? settings.winBack.bonusPoints : settings.birthday.bonusPoints
        AlertPresenter.showTextInput(title: "\(kind.title) bonus", message: StoreAutomationsCopy.bonusPrompt,
                                     placeholder: "0", initialText: current > 0 ? "\(current)" : nil,
                                     keyboardType: .numberPad, confirmTitle: "Save", from: self) { [weak self] text in
            guard let self, let text, let points = Int(text.trimmingCharacters(in: .whitespaces)), points >= 0 else { return }
            var next = self.settings
            if kind == .winBack { next.winBack.bonusPoints = points } else { next.birthday.bonusPoints = points }
            self.save(next)
        }
    }

    // MARK: - Rows

    private func rows(for kind: StoreAutomationsCopy.Kind) -> [Row] {
        var rows: [Row] = [.toggle]
        switch kind {
        case .winBack: rows += [.days, .bonus]
        case .birthday: rows += [.bonus]
        case .almostThere: break
        }
        rows.append(.stats)
        return rows
    }

    private func stat(for kind: StoreAutomationsCopy.Kind) -> StoreAutomationStat? {
        switch kind {
        case .winBack: return stats?.winBack
        case .birthday: return stats?.birthday
        case .almostThere: return stats?.almostThere
        }
    }

    private func isOn(_ kind: StoreAutomationsCopy.Kind) -> Bool {
        switch kind {
        case .winBack: return settings.winBack.enabled
        case .birthday: return settings.birthday.enabled
        case .almostThere: return settings.almostThere.enabled
        }
    }
}

extension VenueAutomationsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { StoreAutomationsCopy.Kind.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows(for: StoreAutomationsCopy.Kind.allCases[section]).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        StoreAutomationsCopy.Kind.allCases[section].title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let kind = StoreAutomationsCopy.Kind.allCases[section]
        return section == StoreAutomationsCopy.Kind.allCases.count - 1
            ? kind.explanation + "\n\n" + StoreAutomationsCopy.pageFooter
            : kind.explanation
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let kind = StoreAutomationsCopy.Kind.allCases[indexPath.section]
        let row = rows(for: kind)[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        switch row {
        case .toggle:
            config.text = "On"
            let toggle = UISwitch()
            toggle.isOn = isOn(kind)
            toggle.tag = indexPath.section
            toggle.addTarget(self, action: #selector(toggled(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .days:
            config.text = "When"
            config.secondaryText = StoreAutomationsCopy.winBackDetail(days: settings.winBack.days)
            cell.accessoryType = .disclosureIndicator
        case .bonus:
            config.text = "Bonus"
            config.secondaryText = StoreAutomationsCopy.bonusLine(kind == .winBack ? settings.winBack.bonusPoints : settings.birthday.bonusPoints)
            cell.accessoryType = .disclosureIndicator
        case .stats:
            let stat = self.stat(for: kind)
            config.text = StoreAutomationsCopy.statsLine(sent: stat?.sent ?? 0, cameBack: stat?.cameBack ?? 0)
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        }
        config.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let kind = StoreAutomationsCopy.Kind.allCases[indexPath.section]
        switch rows(for: kind)[indexPath.row] {
        case .days: pickDays(from: tableView.cellForRow(at: indexPath) ?? tableView)
        case .bonus: editBonus(kind)
        case .toggle, .stats: break
        }
    }
}
