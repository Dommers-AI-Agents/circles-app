import UIKit

class VisitCirclePickerViewController: BaseViewController {
    
    // MARK: - Properties
    var onCirclesSelected: (([String]) -> Void)?
    private var circles: [Circle] = []
    private var selectedCircleIds: Set<String> = []
    
    // MARK: - UI Elements
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "CircleCell")
        table.allowsMultipleSelection = true
        return table
    }()
    
    // MARK: - BaseViewController Configuration
    override var emptyStateMessage: String? {
        "No circles created yet\n\nCreate a circle first to add places to it."
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }
    
    // MARK: - Setup
    private func setupView() {
        title = "Select Circles"
        view.backgroundColor = .systemBackground
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Add",
            style: .done,
            target: self,
            action: #selector(addTapped)
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        guard let userId = AuthService.shared.getUserId() else {
            completion?()
            return
        }
        
        CircleService.shared.fetchUserCircles(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let circles):
                    self?.circles = circles
                    self?.tableView.reloadData()
                    
                case .failure(let error):
                    self?.showError(error)
                }
                completion?()
            }
        }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func addTapped() {
        let selectedIds = Array(selectedCircleIds)
        dismiss(animated: true) { [weak self] in
            self?.onCirclesSelected?(selectedIds)
        }
    }
    
    private func updateAddButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !selectedCircleIds.isEmpty
    }
}

// MARK: - UITableViewDataSource
extension VisitCirclePickerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return circles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CircleCell", for: indexPath)
        let circle = circles[indexPath.row]
        
        cell.textLabel?.text = circle.name
        cell.detailTextLabel?.text = "\(circle.placesCount) places"
        cell.imageView?.image = UIImage(systemName: "circle.fill")
        cell.imageView?.tintColor = Constants.Colors.primary.withAlphaComponent(0.3)
        
        if selectedCircleIds.contains(circle.id) {
            cell.accessoryType = .checkmark
        } else {
            cell.accessoryType = .none
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension VisitCirclePickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let circle = circles[indexPath.row]
        
        if selectedCircleIds.contains(circle.id) {
            selectedCircleIds.remove(circle.id)
            tableView.cellForRow(at: indexPath)?.accessoryType = .none
        } else {
            selectedCircleIds.insert(circle.id)
            tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        updateAddButton()
    }
}