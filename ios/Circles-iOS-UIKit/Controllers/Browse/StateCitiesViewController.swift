import UIKit

/// Second level of the location lens: the cities within a state, with pin
/// counts. Data comes from the already-loaded state node (no extra fetch).
final class StateCitiesViewController: BaseTableViewController {

    private let stateNode: BrowseStateNode

    override var loadsDataOnViewDidLoad: Bool { false }

    init(state: BrowseStateNode) {
        self.stateNode = state
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = stateNode.state
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cityCell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        stateNode.cities.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cityCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "cityCell")
        let city = stateNode.cities[indexPath.row]
        cell.textLabel?.text = city.city
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cell.detailTextLabel?.text = "\(city.count)"
        cell.detailTextLabel?.textColor = Constants.Colors.secondaryLabel
        cell.imageView?.image = UIImage(systemName: "building.2")
        cell.imageView?.tintColor = Constants.Colors.primary
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let city = stateNode.cities[indexPath.row]
        navigationController?.pushViewController(
            CityPlacesViewController(cityKey: city.cityKey, titleText: city.city),
            animated: true
        )
    }
}
