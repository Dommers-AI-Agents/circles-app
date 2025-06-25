import UIKit

class SharedCirclesListViewController: UIViewController {
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .systemGroupedBackground
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return table
    }()
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let emptyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "circle.hexagongrid.circle")
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "No Shared Circles Yet"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emptyDescriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "When your connections share circles with you, they'll appear here."
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Properties
    private var sharedCircles: [CircleShare] = []
    private let cellIdentifier = "SharedCircleCell"
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupTableView()
        setupEmptyState()
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
        view.addSubview(emptyStateView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40)
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
    
    private func setupEmptyState() {
        emptyStateView.addSubview(emptyImageView)
        emptyStateView.addSubview(emptyTitleLabel)
        emptyStateView.addSubview(emptyDescriptionLabel)
        
        NSLayoutConstraint.activate([
            emptyImageView.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyImageView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyImageView.widthAnchor.constraint(equalToConstant: 80),
            emptyImageView.heightAnchor.constraint(equalToConstant: 80),
            
            emptyTitleLabel.topAnchor.constraint(equalTo: emptyImageView.bottomAnchor, constant: 24),
            emptyTitleLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyTitleLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            
            emptyDescriptionLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 8),
            emptyDescriptionLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyDescriptionLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            emptyDescriptionLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    private func loadSharedCircles() {
        NetworkManager.shared.loadSharedCircles()
        
        // Use the published sharedCircles from NetworkManager
        self.sharedCircles = NetworkManager.shared.sharedCircles
        self.tableView.reloadData()
        self.tableView.refreshControl?.endRefreshing()
        
        if self.sharedCircles.isEmpty {
            self.showEmptyState()
        } else {
            self.hideEmptyState()
        }
    }
    
    @objc private func refreshSharedCircles() {
        loadSharedCircles()
    }
    
    // MARK: - Empty State
    private func showEmptyState() {
        emptyStateView.isHidden = false
        tableView.isHidden = true
    }
    
    private func hideEmptyState() {
        emptyStateView.isHidden = true
        tableView.isHidden = false
    }
    
    // MARK: - Navigation
    private func showSharedCircleDetail(_ sharedCircle: CircleShare) {
        let detailVC = SharedCircleDetailViewController()
        detailVC.circleShare = sharedCircle
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension SharedCirclesListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sharedCircles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        let sharedCircle = sharedCircles[indexPath.row]
        
        // Configure cell
        var configuration = cell.defaultContentConfiguration()
        configuration.text = sharedCircle.circle?.name ?? "Unnamed Circle"
        configuration.secondaryText = "Shared by \(sharedCircle.sharedByUser?.displayName ?? "Unknown")"
        configuration.image = UIImage(systemName: "circle.grid.2x2.fill")
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
        let sharedCircle = sharedCircles[indexPath.row]
        showSharedCircleDetail(sharedCircle)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}