import UIKit

class SuggestionsViewController: BaseViewController {
    
    // MARK: - Properties
    private var suggestions: [Suggestion] = []
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .systemGroupedBackground
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        table.register(SuggestionTableViewCell.self, forCellReuseIdentifier: "SuggestionCell")
        return table
    }()
    
    private lazy var createButton: UIButton = {
        let button = UIButton.primaryButton(title: "Share a Suggestion")
        button.addTarget(self, action: #selector(createSuggestionTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - BaseViewController Configuration
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No Suggestions Yet\n\nShare your experiences with your network!" }
    override var reloadsDataOnAppear: Bool { true }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupTableView()
        
        // Mark suggestions as viewed
        SuggestionService.shared.markSuggestionsAsViewed()
        
        // Clear badge
        NotificationCenter.default.post(name: .clearSuggestionsBadge, object: nil)
    }
    
    // MARK: - Setup
    private func setupView() {
        setupNavigationBar(title: "Suggestions")
        addNavigationBarButton(image: "plus", position: .right, action: #selector(createSuggestionTapped))
        
        view.addSubview(tableView)
        view.addSubview(createButton)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            createButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            createButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 100),
            createButton.widthAnchor.constraint(equalToConstant: 180),
            createButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }
    
    // MARK: - Like Management
    private func handleLikeTap(for suggestion: Suggestion) {
        // Find the index of the suggestion
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        
        // Get current user ID
        guard let currentUserId = AuthService.shared.getUserId() else { return }
        
        // Create an updated suggestion with new like state
        let updatedSuggestion: Suggestion
        
        // Optimistically update the UI
        if suggestion.isLikedByCurrentUser {
            // Unlike
            let newLikes = suggestion.likes?.filter { $0 != currentUserId } ?? []
            let newLikesCount = max(0, (suggestion.likesCount ?? 0) - 1)
            updatedSuggestion = suggestion.withUpdatedLikes(likes: newLikes, likesCount: newLikesCount)
        } else {
            // Like
            var newLikes = suggestion.likes ?? []
            newLikes.append(currentUserId)
            let newLikesCount = (suggestion.likesCount ?? 0) + 1
            updatedSuggestion = suggestion.withUpdatedLikes(likes: newLikes, likesCount: newLikesCount)
        }
        
        // Update the suggestions array
        suggestions[index] = updatedSuggestion
        
        // Reload the specific cell
        let indexPath = IndexPath(row: index, section: 0)
        tableView.reloadRows(at: [indexPath], with: .none)
        
        // Make the API call
        if suggestion.isLikedByCurrentUser {
            SuggestionService.shared.unlikeSuggestion(suggestion.id) { [weak self] result in
                switch result {
                case .success:
                    print("Successfully unliked suggestion")
                case .failure(let error):
                    print("Error unliking suggestion: \(error)")
                    // Revert the optimistic update
                    DispatchQueue.main.async {
                        self?.suggestions[index] = suggestion
                        self?.tableView.reloadRows(at: [indexPath], with: .none)
                    }
                }
            }
        } else {
            SuggestionService.shared.likeSuggestion(suggestion.id) { [weak self] result in
                switch result {
                case .success:
                    print("Successfully liked suggestion")
                case .failure(let error):
                    print("Error liking suggestion: \(error)")
                    // Revert the optimistic update
                    DispatchQueue.main.async {
                        self?.suggestions[index] = suggestion
                        self?.tableView.reloadRows(at: [indexPath], with: .none)
                    }
                }
            }
        }
    }
    
    // MARK: - Data Loading (BaseViewController override)
    override func loadData(completion: (() -> Void)? = nil) {
        SuggestionService.shared.fetchNetworkSuggestions { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let suggestions):
                    self?.suggestions = suggestions.filter { !$0.isExpired }
                    self?.tableView.reloadData()
                    self?.updateEmptyState()
                case .failure(let error):
                    print("Error loading suggestions: \(error)")
                    self?.showErrorWithRetry(error) {
                        self?.loadData(completion: completion)
                    }
                }
                completion?()
            }
        }
    }
    
    private func updateEmptyState() {
        if suggestions.isEmpty {
            showEmptyState()
            createButton.isHidden = false
        } else {
            hideEmptyState()
            createButton.isHidden = true
        }
    }
    
    // MARK: - Actions
    @objc private func createSuggestionTapped() {
        let createVC = CreateSuggestionViewController()
        createVC.delegate = self
        let navVC = UINavigationController(rootViewController: createVC)
        present(navVC, animated: true)
    }
    
    private func deleteSuggestion(at indexPath: IndexPath) {
        let suggestion = suggestions[indexPath.row]
        
        AlertPresenter.showConfirmation(
            title: "Delete Suggestion",
            message: "Are you sure you want to delete this suggestion?",
            confirmTitle: "Delete",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in
                let loadingAlert = AlertPresenter.showLoading(message: "Deleting...", from: self!)
                
                SuggestionService.shared.deleteSuggestion(suggestion.id) { result in
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true) {
                            switch result {
                            case .success:
                                self?.suggestions.remove(at: indexPath.row)
                                self?.tableView.deleteRows(at: [indexPath], with: .automatic)
                                self?.updateEmptyState()
                            case .failure(let error):
                                print("Error deleting suggestion: \(error)")
                                self?.showErrorWithRetry(error) {
                                    self?.deleteSuggestion(at: indexPath)
                                }
                            }
                        }
                    }
                }
            }
        )
    }
    
}

// MARK: - UITableViewDataSource
extension SuggestionsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return suggestions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestionCell", for: indexPath) as! SuggestionTableViewCell
        let suggestion = suggestions[indexPath.row]
        cell.configure(with: suggestion)
        cell.delegate = self
        return cell
    }
}

// MARK: - UITableViewDelegate
extension SuggestionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let suggestion = suggestions[indexPath.row]
        // Navigate to suggestion detail view
        let detailVC = SuggestionDetailViewController(suggestion: suggestion)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let suggestion = suggestions[indexPath.row]
        
        // Only allow deletion of own suggestions
        guard suggestion.isCurrentUserSuggestion else { return nil }
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completionHandler in
            self?.deleteSuggestion(at: indexPath)
            completionHandler(true)
        }
        deleteAction.image = UIImage(systemName: "trash")
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: - CreateSuggestionViewControllerDelegate
extension SuggestionsViewController: CreateSuggestionViewControllerDelegate {
    func didCreateSuggestion(_ suggestion: Suggestion) {
        suggestions.insert(suggestion, at: 0)
        tableView.reloadData()
        updateEmptyState()
    }
}

// MARK: - SuggestionTableViewCellDelegate
extension SuggestionsViewController: SuggestionTableViewCellDelegate {
    func suggestionTableViewCell(_ cell: SuggestionTableViewCell, didTapPlace place: Place) {
        // Navigate to place detail view
        let placeDetailVC = PlaceDetailViewController(place: place)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
    
    func suggestionTableViewCell(_ cell: SuggestionTableViewCell, didTapPlaceId placeId: String) {
        // Fetch place details and navigate
        fetchPlaceAndNavigate(placeId: placeId)
    }
    
    func suggestionTableViewCell(_ cell: SuggestionTableViewCell, didTapComments suggestion: Suggestion) {
        // Navigate to suggestion detail view for comments
        let detailVC = SuggestionDetailViewController(suggestion: suggestion)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func suggestionTableViewCell(_ cell: SuggestionTableViewCell, didTapLike suggestion: Suggestion) {
        handleLikeTap(for: suggestion)
    }
    
    private func openPlaceInGoogleMaps(_ place: Place) {
        // Get coordinates from place location
        guard let location = place.location?.clLocation else {
            showError("Location not available for this place")
            return
        }
        
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        
        // Open place in Google Maps
        let googleMapsURL = "comgooglemaps://?q=\(latitude),\(longitude)&center=\(latitude),\(longitude)&zoom=15"
        
        if let url = URL(string: googleMapsURL), UIApplication.shared.canOpenURL(url) {
            // Google Maps is installed, open it
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            // Google Maps not installed, open in web browser
            let webURL = "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)&query_place_id=\(place.googlePlaceId ?? "")"
            if let url = URL(string: webURL) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
    
    private func fetchPlaceAndNavigate(placeId: String) {
        let loadingAlert = AlertPresenter.showLoading(message: "Fetching place details...", from: self)
        
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let place):
                        let placeDetailVC = PlaceDetailViewController(place: place)
                        self?.navigationController?.pushViewController(placeDetailVC, animated: true)
                    case .failure(let error):
                        print("Error fetching place: \(error)")
                        self?.showErrorWithRetry(error) {
                            self?.fetchPlaceAndNavigate(placeId: placeId)
                        }
                    }
                }
            }
        }
    }
}

