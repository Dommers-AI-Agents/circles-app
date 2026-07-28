import UIKit

/// Location browse lens — the "where" way in. Lists the states the user has
/// saved places in (with pin counts), independent of how their circles are
/// organized. Drills State › City › places. Circles are never touched.
final class LocationBrowseViewController: BaseTableViewController {

    private var states: [BrowseStateNode] = []
    private var unplaced: BrowseUnplaced?

    override var emptyStateMessage: String? {
        "No places to browse yet.\nAdd places to your circles and they'll show up here by location."
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Browse by Location"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "stateCell")
    }

    override func loadData(completion: (() -> Void)? = nil) {
        BrowseService.shared.getLocations { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { completion?(); return }
                switch result {
                case .success(let resp):
                    self.states = resp.states
                    self.unplaced = resp.unplaced
                    self.tableView.backgroundView = nil
                    self.tableView.reloadData()
                    if self.states.isEmpty && self.unplaced == nil { self.showEmptyState() }
                case .failure(let error):
                    self.showError(error)
                }
                completion?()
            }
        }
    }

    // MARK: - Table

    private var hasUnplaced: Bool { (unplaced?.count ?? 0) > 0 }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        states.count + (hasUnplaced ? 1 : 0)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "stateCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "stateCell")

        if isUnplacedRow(indexPath) {
            cell.textLabel?.text = "Unplaced"
            cell.detailTextLabel?.text = "\(unplaced?.count ?? 0)"
            cell.imageView?.image = UIImage(systemName: "mappin.slash")
        } else {
            let node = states[indexPath.row]
            cell.textLabel?.text = node.state
            cell.detailTextLabel?.text = "\(node.count)"
            cell.imageView?.image = UIImage(systemName: "mappin.and.ellipse")
        }
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cell.detailTextLabel?.textColor = Constants.Colors.secondaryLabel
        cell.imageView?.tintColor = Constants.Colors.primary
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if isUnplacedRow(indexPath) {
            // Jump straight to the Unplaced list (no city breakdown).
            let vc = CityPlacesViewController(cityKey: unplaced?.cityKey ?? "__unplaced__", titleText: "Unplaced")
            navigationController?.pushViewController(vc, animated: true)
            return
        }

        let node = states[indexPath.row]
        if node.cities.count == 1, let only = node.cities.first {
            // Only one city — skip the intermediate level (adaptive depth).
            let vc = CityPlacesViewController(cityKey: only.cityKey, titleText: only.city)
            navigationController?.pushViewController(vc, animated: true)
        } else {
            navigationController?.pushViewController(StateCitiesViewController(state: node), animated: true)
        }
    }

    private func isUnplacedRow(_ indexPath: IndexPath) -> Bool {
        hasUnplaced && indexPath.row == states.count
    }
}
