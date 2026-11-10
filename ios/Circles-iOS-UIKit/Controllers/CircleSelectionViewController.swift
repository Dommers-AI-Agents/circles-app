import UIKit

protocol CircleSelectionDelegate: AnyObject {
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle)
    func circleSelectionViewControllerDidCancel(_ controller: CircleSelectionViewController)
}

// Extended protocol for place moving functionality
protocol CircleSelectionWithPlaceDelegate: CircleSelectionDelegate {
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle, forPlace place: Place)
}

/// Move a place to another circle (or pick one). Same look as the Add Place
/// circle picker (2026-11-07): "New Circle" first, then the circles with
/// cover, count and privacy; search only once there are enough circles.
class CircleSelectionViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private enum Section: Int, CaseIterable { case create, circles }

    // MARK: - Properties
    
    weak var delegate: CircleSelectionDelegate?
    var placeToMove: Place?
    
    private var circles: [Circle] = []
    private var filteredCircles: [Circle] = []
    private var excludedCircleId: String?
    private var isCreatingNewCircle = false
    private var customTitle: String?
    // A fast double-tap on a circle row fired the delegate twice before the
    // sheet dismissed (double place-move requests) — only the first counts
    private var hasDeliveredSelection = false
    
    // MARK: - UI Components

    /// Only when presented on its own; inside a navigation controller the
    /// controller's own bar is used (a caller wrapped it and got two bars)
    private lazy var navigationBar: UINavigationBar = {
        let navBar = UINavigationBar()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        navBar.setItems([makeNavigationItem(UINavigationItem())], animated: false)
        return navBar
    }()

    private lazy var searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.placeholder = "Search circles"
        bar.searchBarStyle = .minimal
        bar.delegate = self
        bar.sizeToFit()
        return bar
    }()
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(CirclePickerCell.self, forCellReuseIdentifier: CirclePickerCell.reuseId)
        table.register(CirclePickerCreateCell.self, forCellReuseIdentifier: CirclePickerCreateCell.reuseId)
        table.backgroundColor = .clear
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 72
        table.keyboardDismissMode = .onDrag
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
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()
    
    // MARK: - Initialization
    
    init(excludedCircleId: String? = nil, customTitle: String? = nil) {
        self.excludedCircleId = excludedCircleId
        self.customTitle = customTitle
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // The sheet's own (glass) background shows through; grouped elsewhere
        if #available(iOS 26.0, *) {
            view.backgroundColor = .clear
        } else {
            view.backgroundColor = .systemGroupedBackground
        }
        setupUI()
        loadCircles()
    }
    
    // MARK: - Setup

    private func makeNavigationItem(_ item: UINavigationItem) -> UINavigationItem {
        item.title = customTitle ?? (placeToMove != nil ? "Move to Circle" : "Select Circle")
        item.largeTitleDisplayMode = .never
        item.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(cancelTapped))
        return item
    }
    
    private func setupUI() {
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)
        view.addSubview(emptyStateLabel)

        let top: NSLayoutYAxisAnchor
        if navigationController != nil {
            _ = makeNavigationItem(navigationItem)
            top = view.safeAreaLayoutGuide.topAnchor
        } else {
            view.addSubview(navigationBar)
            NSLayoutConstraint.activate([
                navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                navigationBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                navigationBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
            ])
            top = navigationBar.bottomAnchor
        }
        
        // Why a circle (Wes, 2026-11-09): moving a place, or picking one for it
        tableView.tableHeaderView = CirclePickerHeaderView.make(
            headline: CirclePickerCopy.headline(forMove: placeToMove != nil),
            explanation: CirclePickerCopy.explanation(forMove: placeToMove != nil, circleCount: 1),
            width: view.bounds.width)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: top),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadCircles() {
        loadingIndicator.startAnimating()
        tableView.isHidden = true
        emptyStateLabel.isHidden = true
        
        CircleService.shared.fetchUserCircles { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.loadingIndicator.stopAnimating()
                
                switch result {
                case .success(let allCircles):
                    // Keep the server's order (the user's profile arrangement) so this
                    // list matches every other circle list in the app.
                    self.circles = allCircles.filter { $0.id != self.excludedCircleId }
                    self.filteredCircles = self.circles
                    self.tableView.tableHeaderView = CirclePickerRows.showsSearch(circleCount: self.circles.count) ? self.searchBar : nil
                    // "New Circle" is always offered, so the list shows even with no other circles
                    self.tableView.isHidden = false
                    self.tableView.reloadData()
                    
                case .failure(let error):
                    self.tableView.isHidden = true
                    self.emptyStateLabel.isHidden = false
                    self.emptyStateLabel.text = "Couldn't load your circles"
                    self.showError(error)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        delegate?.circleSelectionViewControllerDidCancel(self)
        dismissSheet()
    }

    private func deliver(_ circle: Circle) {
        if let placeDelegate = delegate as? CircleSelectionWithPlaceDelegate, let place = placeToMove {
            placeDelegate.circleSelectionViewController(self, didSelectCircle: circle, forPlace: place)
        } else {
            delegate?.circleSelectionViewController(self, didSelectCircle: circle)
        }
        dismissSheet()
    }
    
    private func createNewCircle() {
        AlertPresenter.showTextInput(
            title: "New Circle",
            message: "Enter a name for the new circle",
            placeholder: "Circle name",
            autocapitalization: .words,
            confirmTitle: "Create",
            from: self
        ) { [weak self] text in
            guard let self, let name = text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            // A circle with this name already exists
            if let existing = self.circles.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                self.showDuplicateCircleAlert(existingName: name, existingCircle: existing)
                return
            }
            self.createCircleWithName(name)
        }
    }
    
    private func showDuplicateCircleAlert(existingName: String, existingCircle: Circle) {
        AlertPresenter.showAlert(
            title: "Circle Already Exists",
            message: "A circle named '\(existingName)' already exists. Would you like to add anyway or select the existing circle?",
            actions: [
                (title: "Add Anyway", style: .default, handler: { [weak self] in self?.createCircleWithName(existingName) }),
                (title: "Use Existing", style: .default, handler: { [weak self] in self?.deliver(existingCircle) }),
                (title: "Cancel", style: .cancel, handler: {})
            ],
            from: self
        )
    }
    
    private func createCircleWithName(_ name: String) {
        isCreatingNewCircle = true
        loadingIndicator.startAnimating()
        
        CircleService.shared.createCircle(name: name, description: nil, privacy: .public, category: .other) { result in
            DispatchQueue.main.async {
                self.isCreatingNewCircle = false
                self.loadingIndicator.stopAnimating()
                
                switch result {
                case .success(let circle):
                    self.deliver(circle)
                    
                case .failure(let error):
                    // At the free-tier circle cap the server says so with a
                    // 403 — offer the upgrade, not a dead-end error
                    if !SubscriptionManager.shared.presentPaywallIfLimitError(error, from: self, reason: .circleLimit) {
                        self.showError(error)
                    }
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension CircleSelectionViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .create: return (searchBar.text ?? "").isEmpty ? 1 : 0
        case .circles: return filteredCircles.count
        case .none: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if Section(rawValue: indexPath.section) == .create {
            return tableView.dequeueReusableCell(withIdentifier: CirclePickerCreateCell.reuseId, for: indexPath)
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: CirclePickerCell.reuseId, for: indexPath) as! CirclePickerCell
        cell.configure(with: filteredCircles[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard Section(rawValue: section) == .circles, !filteredCircles.isEmpty else { return nil }
        return excludedCircleId != nil ? "Your other circles" : "Your circles"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .circles, filteredCircles.isEmpty else { return nil }
        if !circles.isEmpty { return "No circles match." }
        return excludedCircleId != nil ? "You don't have another circle yet. Make one above." : nil
    }
}

// MARK: - UITableViewDelegate

extension CircleSelectionViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if Section(rawValue: indexPath.section) == .create {
            createNewCircle()
            return
        }
        guard !hasDeliveredSelection, indexPath.row < filteredCircles.count else { return }
        hasDeliveredSelection = true
        deliver(filteredCircles[indexPath.row])
    }
}

// MARK: - UISearchBarDelegate

extension CircleSelectionViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        filteredCircles = CirclePickerRows.filter(circles, query: searchText)
        tableView.reloadData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
