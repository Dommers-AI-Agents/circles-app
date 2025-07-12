import UIKit

protocol CircleSelectionDelegate: AnyObject {
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle)
    func circleSelectionViewControllerDidCancel(_ controller: CircleSelectionViewController)
}

class CircleSelectionViewController: UIViewController {
    // MARK: - Properties
    
    weak var delegate: CircleSelectionDelegate?
    
    private var circles: [Circle] = []
    private var excludedCircleId: String?
    private var isCreatingNewCircle = false
    
    // MARK: - UI Components
    
    private lazy var navigationBar: UINavigationBar = {
        let navBar = UINavigationBar()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        let navItem = UINavigationItem(title: "Select Circle")
        
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navItem.leftBarButtonItem = cancelButton
        
        navBar.setItems([navItem], animated: false)
        return navBar
    }()
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "CircleCell")
        return table
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "No circles available"
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        label.isHidden = true
        return label
    }()
    
    // MARK: - Initialization
    
    init(excludedCircleId: String? = nil) {
        self.excludedCircleId = excludedCircleId
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        loadCircles()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(navigationBar)
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)
        view.addSubview(emptyStateLabel)
        
        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            tableView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadCircles() {
        loadingIndicator.startAnimating()
        tableView.isHidden = true
        emptyStateLabel.isHidden = true
        
        CircleService.shared.fetchUserCircles { [weak self] (result: Result<[Circle], Error>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.loadingIndicator.stopAnimating()
                
                switch result {
                case .success(let allCircles):
                    // Filter out the excluded circle if provided
                    if let excludedId = self.excludedCircleId {
                        self.circles = allCircles.filter { $0.id != excludedId }
                    } else {
                        self.circles = allCircles
                    }
                    
                    if self.circles.isEmpty {
                        self.tableView.isHidden = true
                        self.emptyStateLabel.isHidden = false
                        self.emptyStateLabel.text = "No other circles available"
                    } else {
                        self.tableView.isHidden = false
                        self.emptyStateLabel.isHidden = true
                        self.tableView.reloadData()
                    }
                    
                case .failure(let error):
                    self.tableView.isHidden = true
                    self.emptyStateLabel.isHidden = false
                    self.emptyStateLabel.text = "Failed to load circles"
                    self.showError(error)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        delegate?.circleSelectionViewControllerDidCancel(self)
        dismiss(animated: true)
    }
    
    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func createNewCircle() {
        let alert = UIAlertController(title: "New Circle", message: "Enter a name for the new circle", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Circle name"
            textField.autocapitalizationType = .words
        }
        
        let createAction = UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self,
                  let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return }
            
            self.isCreatingNewCircle = true
            self.loadingIndicator.startAnimating()
            
            CircleService.shared.createCircle(name: name, description: nil, privacy: .myNetwork, category: .other) { result in
                DispatchQueue.main.async {
                    self.isCreatingNewCircle = false
                    self.loadingIndicator.stopAnimating()
                    
                    switch result {
                    case .success(let circle):
                        self.delegate?.circleSelectionViewController(self, didSelectCircle: circle)
                        self.dismiss(animated: true)
                        
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(createAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension CircleSelectionViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 // 1 for existing circles, 1 for create new
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return circles.count
        } else {
            return 1 // Create new circle option
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CircleCell", for: indexPath)
        
        if indexPath.section == 0 {
            let circle = circles[indexPath.row]
            cell.textLabel?.text = circle.name
            cell.detailTextLabel?.text = "\(circle.placesCount ?? 0) places"
            cell.accessoryType = .none
        } else {
            cell.textLabel?.text = "Create New Circle"
            cell.textLabel?.textColor = .systemBlue
            cell.accessoryType = .none
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension CircleSelectionViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 0 {
            let selectedCircle = circles[indexPath.row]
            delegate?.circleSelectionViewController(self, didSelectCircle: selectedCircle)
            dismiss(animated: true)
        } else {
            createNewCircle()
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 && !circles.isEmpty {
            return "Your Circles"
        }
        return nil
    }
}