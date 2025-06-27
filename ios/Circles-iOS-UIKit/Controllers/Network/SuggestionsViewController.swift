import UIKit

class SuggestionsViewController: UIViewController {
    
    // MARK: - Properties
    private var suggestions: [Suggestion] = []
    private let refreshControl = UIRefreshControl()
    
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
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let emptyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "bubble.left.and.bubble.right")
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "No Suggestions Yet"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emptyDescriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Share your experiences with your network!"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let createButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Share a Suggestion", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = Constants.Colors.primary
        button.tintColor = .white
        button.layer.cornerRadius = 22
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupTableView()
        setupEmptyState()
        loadSuggestions()
        
        // Mark suggestions as viewed
        SuggestionService.shared.markSuggestionsAsViewed()
        
        // Clear badge
        NotificationCenter.default.post(name: .clearSuggestionsBadge, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSuggestions()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemGroupedBackground
        title = "Suggestions"
        
        // Add right bar button for creating suggestion
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .compose,
            target: self,
            action: #selector(createSuggestionTapped)
        )
        
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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
        
        refreshControl.addTarget(self, action: #selector(refreshSuggestions), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupEmptyState() {
        emptyStateView.addSubview(emptyImageView)
        emptyStateView.addSubview(emptyTitleLabel)
        emptyStateView.addSubview(emptyDescriptionLabel)
        emptyStateView.addSubview(createButton)
        
        createButton.addTarget(self, action: #selector(createSuggestionTapped), for: .touchUpInside)
        
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
            
            createButton.topAnchor.constraint(equalTo: emptyDescriptionLabel.bottomAnchor, constant: 24),
            createButton.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            createButton.widthAnchor.constraint(equalToConstant: 180),
            createButton.heightAnchor.constraint(equalToConstant: 44),
            createButton.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
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
    
    // MARK: - Data Loading
    private func loadSuggestions() {
        SuggestionService.shared.fetchNetworkSuggestions { [weak self] result in
            DispatchQueue.main.async {
                self?.refreshControl.endRefreshing()
                
                switch result {
                case .success(let suggestions):
                    self?.suggestions = suggestions.filter { !$0.isExpired }
                    self?.tableView.reloadData()
                    self?.updateEmptyState()
                case .failure(let error):
                    print("Error loading suggestions: \(error)")
                    self?.showError("Failed to load suggestions")
                }
            }
        }
    }
    
    @objc private func refreshSuggestions() {
        loadSuggestions()
    }
    
    private func updateEmptyState() {
        let isEmpty = suggestions.isEmpty
        emptyStateView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
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
        
        let alert = UIAlertController(
            title: "Delete Suggestion",
            message: "Are you sure you want to delete this suggestion?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            SuggestionService.shared.deleteSuggestion(suggestion.id) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.suggestions.remove(at: indexPath.row)
                        self?.tableView.deleteRows(at: [indexPath], with: .automatic)
                        self?.updateEmptyState()
                    case .failure(let error):
                        print("Error deleting suggestion: \(error)")
                        self?.showError("Failed to delete suggestion")
                    }
                }
            }
        })
        
        present(alert, animated: true)
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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
        openPlaceInGoogleMaps(place)
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
        // Show loading
        let loadingAlert = UIAlertController(title: "Loading", message: "Fetching place details...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Fetch place details
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true, completion: {
                    switch result {
                    case .success(let place):
                        self?.openPlaceInGoogleMaps(place)
                    case .failure(let error):
                        print("Error fetching place: \(error)")
                        self?.showError("Could not load place details")
                    }
                })
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let clearSuggestionsBadge = Notification.Name("clearSuggestionsBadge")
    static let suggestionsBadgeUpdate = Notification.Name("suggestionsBadgeUpdate")
}