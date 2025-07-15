import UIKit

class SharedCirclesListViewController: BaseViewController {
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .systemGroupedBackground
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return table
    }()
    
    // MARK: - BaseViewController Configuration
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No Editable Circles Yet\n\nWhen your connections share circles with you and allow you to edit them, they'll appear here." }
    
    // MARK: - Properties
    private var editableCircles: [Circle] = []
    private let cellIdentifier = "SharedCircleCell"
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupTableView()
        loadSharedCircles()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSharedCircles()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemGroupedBackground
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)
        
        // Add refresh control
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshSharedCircles), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        NetworkManager.shared.loadEditableCirclesFromOthers()
        
        // Use the published editableCirclesFromOthers from NetworkManager
        self.editableCircles = NetworkManager.shared.editableCirclesFromOthers
        self.tableView.reloadData()
        
        completion?()
    }
    
    private func loadSharedCircles() {
        loadData()
    }
    
    @objc private func refreshSharedCircles() {
        loadSharedCircles()
    }
    
    
    // MARK: - Navigation
    private func showCircleDetail(_ circle: Circle) {
        let detailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension SharedCirclesListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return editableCircles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        let circle = editableCircles[indexPath.row]
        
        // Configure cell
        var configuration = cell.defaultContentConfiguration()
        configuration.text = circle.name
        configuration.secondaryText = "Shared by \(circle.ownerDetails?.displayName ?? "Unknown")"
        
        // Set icon based on category
        switch circle.category {
        case .travel:
            configuration.image = UIImage(systemName: "airplane")
        case .food:
            configuration.image = UIImage(systemName: "fork.knife")
        case .services:
            configuration.image = UIImage(systemName: "wrench.and.screwdriver")
        case .shopping:
            configuration.image = UIImage(systemName: "bag")
        case .healthcare:
            configuration.image = UIImage(systemName: "heart")
        case .entertainment:
            configuration.image = UIImage(systemName: "tv")
        default:
            configuration.image = UIImage(systemName: "circle.grid.2x2.fill")
        }
        
        configuration.imageProperties.tintColor = Constants.Colors.primary
        
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension SharedCirclesListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let circle = editableCircles[indexPath.row]
        showCircleDetail(circle)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}