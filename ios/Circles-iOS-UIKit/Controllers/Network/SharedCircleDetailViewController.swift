import UIKit

class SharedCircleDetailViewController: BaseViewController {
    
    // MARK: - Properties
    var circleShare: CircleShare?
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .grouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let circleImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "circle.grid.2x2.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let circleNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let sharedByLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Properties
    private var places: [Place] = []
    private let cellIdentifier = "PlaceCell"
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        configureView()
        loadPlaces()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        title = "Shared Circle"
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        setupTableView()
        setupHeaderView()
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)
    }
    
    private func setupHeaderView() {
        headerView.backgroundColor = .systemBackground
        
        headerView.addSubview(circleImageView)
        headerView.addSubview(circleNameLabel)
        headerView.addSubview(sharedByLabel)
        
        NSLayoutConstraint.activate([
            circleImageView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20),
            circleImageView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            circleImageView.widthAnchor.constraint(equalToConstant: 80),
            circleImageView.heightAnchor.constraint(equalToConstant: 80),
            
            circleNameLabel.topAnchor.constraint(equalTo: circleImageView.bottomAnchor, constant: 16),
            circleNameLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            circleNameLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            
            sharedByLabel.topAnchor.constraint(equalTo: circleNameLabel.bottomAnchor, constant: 4),
            sharedByLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            sharedByLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            sharedByLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -20)
        ])
        
        headerView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 180)
        tableView.tableHeaderView = headerView
    }
    
    private func configureView() {
        guard let circleShare = circleShare else { return }
        
        circleNameLabel.text = circleShare.circle?.name ?? "Unnamed Circle"
        
        let sharedByName = circleShare.sharedByUser?.displayName ?? "Someone"
        sharedByLabel.text = "Shared by \(sharedByName)"
    }
    
    // MARK: - Data Loading
    private func loadPlaces() {
        guard let circleId = circleShare?.circle?.id else { return }
        
        PlaceService.shared.fetchPlacesByCircleId(circleId: circleId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let fetchedPlaces):
                    self?.places = fetchedPlaces
                    self?.tableView.reloadData()
                case .failure(let error):
                    print("Error loading places: \(error)")
                }
            }
        }
    }
    
    // MARK: - Navigation
    private func showPlaceDetail(_ place: Place) {
        let placeDetailVC = PlaceDetailViewController(place: place, circle: circleShare?.circle)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension SharedCircleDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return places.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        let place = places[indexPath.row]
        
        var configuration = cell.defaultContentConfiguration()
        configuration.text = place.name
        configuration.secondaryText = place.address
        configuration.image = UIImage(systemName: place.category.systemIconName)
        configuration.imageProperties.tintColor = Constants.Colors.primary
        
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return places.isEmpty ? nil : "Places (\(places.count))"
    }
}

// MARK: - UITableViewDelegate
extension SharedCircleDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let place = places[indexPath.row]
        showPlaceDetail(place)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}