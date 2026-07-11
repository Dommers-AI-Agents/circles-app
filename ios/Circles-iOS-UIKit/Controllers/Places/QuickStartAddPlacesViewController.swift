import UIKit
import MapKit

/// Lightweight first-session flow: search a place, tap it, it's saved into the
/// user's default circle. No forms, no pickers — three taps for three places.
/// Reached from the home screen's empty state.
class QuickStartAddPlacesViewController: BaseViewController {

    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    // MARK: - Properties
    private let targetCircle: Circle
    private var results: [MKMapItem] = []
    private var addedResultKeys: Set<String> = []
    private var savingResultKeys: Set<String> = []
    private var addedCount = 0
    private var searchTimer: Timer?

    // MARK: - UI Elements
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Add 3 places you love"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Search for your favorite spots — tap to add them"
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search restaurants, cafes, shops…"
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()

    private let resultsTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.rowHeight = 60
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "QuickStartResultCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private lazy var doneButton = UIButton.primaryButton(title: "Done")

    // MARK: - Init
    init(targetCircle: Circle) {
        self.targetCircle = targetCircle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        setupUI()
        searchBar.delegate = self
        resultsTableView.delegate = self
        resultsTableView.dataSource = self
        updateDoneButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    // MARK: - Setup
    private func setupUI() {
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(searchBar)
        view.addSubview(resultsTableView)
        view.addSubview(doneButton)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            searchBar.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            resultsTableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            resultsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsTableView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -12),

            doneButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    // MARK: - Search
    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            resultsTableView.reloadData()
            return
        }

        AppleMapsService.shared.searchPlaces(query: trimmed) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let items) = result {
                    self.results = items
                    self.resultsTableView.reloadData()
                }
            }
        }
    }

    private func resultKey(for item: MKMapItem) -> String {
        let coordinate = item.placemark.coordinate
        return "\(item.name ?? "")|\(coordinate.latitude)|\(coordinate.longitude)"
    }

    // MARK: - Adding
    private func addPlace(from item: MKMapItem) {
        let key = resultKey(for: item)
        guard !addedResultKeys.contains(key), !savingResultKeys.contains(key) else { return }
        savingResultKeys.insert(key)
        resultsTableView.reloadData()

        let details = AppleMapsService.shared.fetchPlaceDetails(mapItem: item)

        PlaceService.shared.createPlace(
            name: details.name,
            description: nil,
            address: details.address,
            category: details.category,
            circleId: targetCircle.id,
            website: details.website,
            phone: details.phoneNumber,
            location: details.coordinate
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.savingResultKeys.remove(key)

                switch result {
                case .success:
                    self.addedResultKeys.insert(key)
                    self.addedCount += 1
                    self.updateDoneButton()
                    // Let the home screen refresh its map/data
                    NotificationCenter.default.post(name: Notification.Name("PlaceAdded"), object: nil)
                case .failure(let error):
                    self.showError(error)
                }
                self.resultsTableView.reloadData()
            }
        }
    }

    private func updateDoneButton() {
        switch addedCount {
        case 0:
            doneButton.setTitle("Skip for Now", for: .normal)
        case 1, 2:
            doneButton.setTitle("Done (\(addedCount) added — add more!)", for: .normal)
        default:
            doneButton.setTitle("Done 🎉 (\(addedCount) added)", for: .normal)
        }
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UISearchBarDelegate
extension QuickStartAddPlacesViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.performSearch(query: searchText)
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        performSearch(query: searchBar.text ?? "")
    }
}

// MARK: - UITableViewDataSource & Delegate
extension QuickStartAddPlacesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "QuickStartResultCell", for: indexPath)
        guard indexPath.row < results.count else { return cell }

        let item = results[indexPath.row]
        let key = resultKey(for: item)

        var config = cell.defaultContentConfiguration()
        config.text = item.name
        config.secondaryText = item.placemark.title
        config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
        config.secondaryTextProperties.numberOfLines = 1
        cell.contentConfiguration = config
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        if addedResultKeys.contains(key) {
            let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
            check.tintColor = .systemGreen
            cell.accessoryView = check
        } else if savingResultKeys.contains(key) {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessoryView = spinner
        } else {
            let plus = UIImageView(image: UIImage(systemName: "plus.circle"))
            plus.tintColor = Constants.Colors.primary
            cell.accessoryView = plus
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < results.count else { return }
        addPlace(from: results[indexPath.row])
    }
}
