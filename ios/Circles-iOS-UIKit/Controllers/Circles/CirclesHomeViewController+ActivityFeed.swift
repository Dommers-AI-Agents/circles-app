import UIKit
import CoreLocation
import ObjectiveC

// Activity-feed cell, reaction picker, notification-navigation, and
// swipe-action handling for CirclesHomeViewController. Extracted (Wave 4).

private var momentOpenInFlightKey: UInt8 = 0

extension CirclesHomeViewController {
    /// Guards against the same moment-open firing twice. A single activity-row
    /// tap can trigger BOTH `tableView(_:didSelectRowAt:)` (→ `navigateToVideo`)
    /// and the cell's content-tap gesture (→ `navigateToVideoFromActivity`),
    /// which otherwise stacks two "Loading video..." alerts and fires two
    /// detail requests. Reset once the open resolves (present or error).
    fileprivate var isOpeningMoment: Bool {
        get { (objc_getAssociatedObject(self, &momentOpenInFlightKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &momentOpenInFlightKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: - ActivityFeedCellDelegate
extension CirclesHomeViewController: ActivityFeedCellDelegate {
    func didTapUserProfile(user: User) {
        // Navigate to user's profile
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    func didTapActivityContent(activity: Activity) {
        // Navigate based on activity type
        switch activity.type {
        case .videoUploaded, .videoLiked:
            // For moment upload/like activities, open the moment player
            // (targetId is the video id in both cases)
            navigateToVideoFromActivity(activity)
        case .placeAdded, .placeLiked, .placeCommented, .checkIn:
            // For place-related activities, navigate to place detail
            navigateToPlaceFromActivity(activity)
        default:
            break
        }
    }

    func didTapActivityGroup(activities: [Activity]) {
        // Expand/collapse the summary row so every activity in the burst is
        // visible as its own tappable row beneath it
        guard let first = activities.first else { return }
        toggleActivityGroup(withKey: first.id)
    }
    
    func didTapPlaceImage(activity: Activity) {
        // The thumbnail on a moment activity is the moment itself — open the
        // player, not a place lookup (which 404s: these have no place detail).
        switch activity.type {
        case .videoUploaded, .videoLiked:
            navigateToVideoFromActivity(activity)
        default:
            navigateToPlaceFromActivity(activity)
        }
    }
    
    func navigateToVideoFromActivity(_ activity: Activity) {
        // The targetId contains the video ID for video upload/like activities
        let videoId = activity.targetId
        guard !videoId.isEmpty, !isOpeningMoment else { return }
        isOpeningMoment = true

        // Fetch the moment, then drop the user into the inline Moments tab
        // positioned on it (rather than a separate full-screen player).
        APIService.shared.request(
            endpoint: "videos/\(videoId)",
            method: .get
        ) { [weak self] (result: Result<PlaceVideoResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isOpeningMoment = false
                switch result {
                case .success(let response):
                    self.openMomentInMomentsTab(response.data)
                case .failure(let error):
                    // Prefer the server's friendly, actionable message (e.g.
                    // "You're not connected to X. Send them a connection
                    // request to view this moment.") over a generic string.
                    self.showError(error.serverMessage ?? "Unable to load this moment. Please try again.")
                }
            }
        }
    }

    func navigateToPlaceFromActivity(_ activity: Activity) {
        // For video uploads, use placeId from metadata; for check-ins use metadata placeId; otherwise use targetId
        let placeId: String
        if activity.type == .videoUploaded || activity.type == .checkIn {
            placeId = activity.metadata?.placeId ?? ""
        } else {
            placeId = activity.targetId
        }
        guard !placeId.isEmpty else { return }
        
        Logger.info("🔍 navigateToPlaceFromActivity: Attempting to navigate to place")
        Logger.info("🔍 Activity type: \(activity.type)")
        Logger.info("🔍 Activity target: \(activity.targetName)")
        Logger.info("🔍 PlaceId: \(placeId)")
        Logger.info("🔍 CircleId: \(activity.circleId ?? "none")")
        Logger.info("🔍 Actor: \(activity.actor?.displayName ?? "unknown")")
        
        // Try to find the place in an existing circle
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] (result: Result<Place, Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let place):
                    Logger.info("✅ Successfully fetched place: \(place.name)")
                    let detailVC = PlaceDetailViewController(place: place)
                    self?.navigationController?.pushViewController(detailVC, animated: true)
                case .failure(let error):
                    Logger.error("❌ Failed to fetch place \(placeId): \(error.localizedDescription)")
                    // If we can't fetch the place (likely because it's not in a user's circle),
                    // create a temporary place object from the activity metadata for check-ins and video uploads
                    if activity.type == .checkIn || activity.type == .videoUploaded {
                        let placeName = activity.targetName
                        
                        // Show a simple place view with limited functionality
                        let tempPlaceVC = TempPlaceDetailViewController()
                        tempPlaceVC.configure(
                            placeId: placeId,
                            name: placeName,
                            address: activity.metadata?.placeAddress ?? "",
                            latitude: activity.metadata?.latitude,
                            longitude: activity.metadata?.longitude,
                            photo: activity.metadata?.placePhoto
                        )
                        self?.navigationController?.pushViewController(tempPlaceVC, animated: true)
                    } else {
                        self?.showError("Unable to load place details")
                    }
                }
            }
        }
    }
    
    func didTapReactions(activity: Activity) {
        // Show unified engagement view (LinkedIn-style)
        let engagementVC = ActivityEngagementViewController(activity: activity)
        let navController = UINavigationController(rootViewController: engagementVC)
        present(navController, animated: true)
    }
    
    func didTapComments(activity: Activity) {
        // Show comments view
        let commentsVC = ActivityCommentsViewController(activity: activity)
        commentsVC.onCommentsUpdated = { [weak self] commentCount in
            // Update the row in place — a full refresh would jump the user
            // back to the top of the feed when they close the comments sheet
            guard let self = self,
                  let index = self.activities.firstIndex(where: { $0.id == activity.id }) else { return }
            self.activities[index] = self.activities[index].withCommentCount(commentCount)
            self.regroupActivities()
            self.activityTableView.reloadData()
        }
        let navController = UINavigationController(rootViewController: commentsVC)
        present(navController, animated: true)
    }
    
    /// Reaction response: the piggyBank stub rides along (same shape as
    /// create-place) so the coin-drop can play for the nickel earn
    private struct ReactionResponse: Decodable {
        let success: Bool
        let piggyBank: PiggyBankCredit?
    }

    func didTapReactionButton(activity: Activity, emoji: String) {
        // Toggle reaction - if user already has this reaction, remove it, otherwise add it
        let isRemoving = activity.userReaction == emoji
        let endpoint = isRemoving ?
            "activities/\(activity.id)/reactions/remove" :
            "activities/\(activity.id)/reactions"

        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: ["emoji": emoji]
        ) { [weak self] (result: Result<ReactionResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    // Update the row in place. A full fetchActivities() here
                    // would reset pagination to page one and jump the user
                    // back to the top of the feed mid-scroll.
                    self?.applyLocalReaction(activityId: activity.id, emoji: isRemoving ? nil : emoji)
                    // First reaction on someone else's activity earns a
                    // nickel — play the deposit (no-op when nothing credited)
                    if !isRemoving {
                        PiggyBankDepositView.play(credit: response.piggyBank)
                    }
                case .failure(let error):
                    // 404 means the activity was deleted after our feed loaded
                    // it (actor removed the place or swiped the row away) —
                    // the row is stale, so drop it instead of surfacing an error
                    if case .httpError(404, _) = error {
                        self?.removeStaleActivity(id: activity.id)
                    } else {
                        self?.showError("Failed to update reaction: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Drops a feed row whose backing activity no longer exists server-side
    func removeStaleActivity(id: String) {
        guard activities.contains(where: { $0.id == id }) else { return }
        activities.removeAll { $0.id == id }
        regroupActivities()
        activityTableView.reloadData()
    }

    /// Applies a reaction toggle to the in-memory feed and reloads the table
    /// without touching scroll position; the next natural feed load brings
    /// the server-computed counts.
    func applyLocalReaction(activityId: String, emoji: String?) {
        guard let index = activities.firstIndex(where: { $0.id == activityId }) else { return }
        let current = activities[index]

        var count = current.reactionCount ?? 0
        if emoji == nil {
            count = max(0, count - 1)
        } else if current.userReaction == nil {
            count += 1
        } // switching from one emoji to another keeps the count

        // Keep the reaction chips consistent with the toggle
        var summary = current.reactionSummary ?? []
        if let old = current.userReaction, let i = summary.firstIndex(where: { $0.emoji == old }) {
            if summary[i].count <= 1 {
                summary.remove(at: i)
            } else {
                summary[i] = ReactionSummary(emoji: old, count: summary[i].count - 1, users: nil)
            }
        }
        if let emoji = emoji {
            if let i = summary.firstIndex(where: { $0.emoji == emoji }) {
                summary[i] = ReactionSummary(emoji: emoji, count: summary[i].count + 1, users: nil)
            } else {
                summary.append(ReactionSummary(emoji: emoji, count: 1, users: nil))
            }
        }

        activities[index] = current.withReaction(
            userReaction: emoji,
            reactionCount: count,
            reactionSummary: summary.isEmpty ? nil : summary
        )
        regroupActivities()
        activityTableView.reloadData()
    }
    
    func didLongPressReactionButton(activity: Activity, sourceView: UIView) {
        // Create and show reaction picker
        let reactionPicker = ReactionPickerView()
        reactionPicker.delegate = self
        reactionPicker.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to view hierarchy
        view.addSubview(reactionPicker)
        
        // Constrain to fill the view
        NSLayoutConstraint.activate([
            reactionPicker.topAnchor.constraint(equalTo: view.topAnchor),
            reactionPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reactionPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            reactionPicker.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Store activity for later use
        currentReactionActivity = activity
        
        // Show picker near the source view
        reactionPicker.show(from: sourceView)
    }
}

// MARK: - ReactionPickerDelegate
extension CirclesHomeViewController: ReactionPickerDelegate {
    func reactionPicker(_ picker: ReactionPickerView, didSelectReaction reaction: ReactionStyle) {
        guard let activity = currentReactionActivity else { return }
        
        // Send reaction to server
        didTapReactionButton(activity: activity, emoji: reaction.rawValue)
        
        // Clear stored activity
        currentReactionActivity = nil
    }
    
    func reactionPickerDidDismiss(_ picker: ReactionPickerView) {
        // Clear stored activity
        currentReactionActivity = nil
    }
}

// MARK: - Navigation from Notifications
extension CirclesHomeViewController {
    func scrollToTop() {
        DispatchQueue.main.async {
            self.scrollView.setContentOffset(.zero, animated: true)
            // The activity table scrolls independently of the outer scroll
            // view — reset it too so a Home re-tap always lands at the top
            // of the feed
            if !self.activityTableView.isHidden, self.activityTableView.window != nil {
                self.activityTableView.setContentOffset(
                    CGPoint(x: 0, y: -self.activityTableView.contentInset.top),
                    animated: true
                )
            }
        }
    }

    /// Tab-bar Home re-tap: return the content segment to the Activity tab
    /// (from Moments/Specials) so Home always opens on Activity.
    func resetContentTabToActivity() {
        guard contentSegmentedControl.selectedSegmentIndex != 0 else { return }
        contentSegmentedControl.selectedSegmentIndex = 0
        contentSegmentChanged()
    }

    /// Tab-bar Home re-tap: return the map to its original state — no
    /// connection or category filter, framed on the default region, and back
    /// to map (not list) view.
    func resetMapToDefault() {
        resetPlacesListToMap()

        // Chip filters (category group + region) live inside the embedded map.
        mapViewController?.resetChipFilters()

        // Original load state is "Everyone" (nil) — the map header opens on your
        // network scope, All Categories · All Places.
        if selectedConnectionId != nil || selectedCategory != nil {
            selectedCategory = nil
            selectConnection(id: nil, user: nil)
        } else {
            // Nothing filtered - just re-frame the default region (the user
            // may have panned or zoomed away)
            mapViewController?.adjustMapRegion()
        }
    }


    /// Venue offer/announcement activities target the canonical venue record
    /// (globalPlaceId), not a personal save doc — resolve it the same way the
    /// Specials tab does and open the place page
    func navigateToGlobalPlace(withId globalPlaceId: String) {
        let loading = AlertPresenter.showLoading(message: "Loading place...", from: self)
        GlobalPlaceService.shared.getGlobalPlace(id: globalPlaceId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let response):
                        let place = response.bestDetailPlace()
                        let detailVC = PlaceDetailViewController(place: place)
                        self.navigationController?.pushViewController(detailVC, animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    func navigateToCircle(withId circleId: String) {
        // Find the circle in our data
        guard let circle = circles.first(where: { $0.id == circleId }) else {
            // If circle not found, try to load it
            loadCircleAndNavigate(circleId: circleId)
            return
        }
        
        // Navigate to circle detail
        let detailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func loadCircleAndNavigate(circleId: String) {
        // Show loading
        let loadingAlert = UIAlertController(title: "Loading", message: "Loading circle...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        CircleService.shared.fetchCircleById(id: circleId) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let circle):
                        let detailVC = CircleDetailViewController(circle: circle)
                        self.navigationController?.pushViewController(detailVC, animated: true)
                    case .failure(let error):
                        let alert = UIAlertController(
                            title: "Error",
                            message: "Failed to load circle: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    func navigateToPlace(withId placeId: String) {
        // Try to find the place in our loaded data first
        if let place = allPlaces.first(where: { $0.id == placeId }) {
            // Find the circle for this place
            if let circle = circles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            } else if let networkCircle = networkCircles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: networkCircle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            }
        } else {
            // If not found, load the place
            loadPlaceAndNavigate(placeId: placeId)
        }
    }
    
    func navigateToVideo(withId videoId: String) {
        // A blank id would hit `GET /videos/` → server 500; and a duplicate tap
        // (see `isOpeningMoment`) would double-open.
        guard !videoId.isEmpty, !isOpeningMoment else { return }
        isOpeningMoment = true

        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Loading video...", from: self)

        // Fetch the moment, then drop into the inline Moments tab on it.
        APIService.shared.request(
            endpoint: "videos/\(videoId)",
            method: .get
        ) { [weak self] (result: Result<VideoResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    self.isOpeningMoment = false

                    switch result {
                    case .success(let response):
                        self.openMomentInMomentsTab(response.data)
                    case .failure(let error):
                        self.showError(error.serverMessage ?? "Unable to load this moment. Please try again.")
                    }
                }
            }
        }
    }
    
    func navigateToCheckInPlace(activity: Activity) {
        // First check if we have the place ID and can find it in our loaded data
        if let placeId = activity.metadata?.placeId,
           let place = allPlaces.first(where: { $0.id == placeId }) {
            // Found the place in our data, navigate normally
            if let circle = circles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            } else if let networkCircle = networkCircles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: networkCircle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            } else {
                // Place exists but not in a circle (floating place), still show it
                let placeDetailVC = PlaceDetailViewController(place: place, circle: nil)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            }
        } else if let placeId = activity.metadata?.placeId {
            // Have a place ID but not in our data, try to load it
            // But if it fails, fall back to creating from metadata
            PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let place):
                        // Successfully loaded the place
                        let placeDetailVC = PlaceDetailViewController(place: place, circle: nil)
                        self?.navigationController?.pushViewController(placeDetailVC, animated: true)
                    case .failure:
                        // Failed to load, create from metadata
                        self?.navigateToCheckInPlaceFromMetadata(activity: activity)
                    }
                }
            }
        } else {
            // No place ID, create from metadata
            navigateToCheckInPlaceFromMetadata(activity: activity)
        }
    }
    
    func navigateToCheckInPlaceFromMetadata(activity: Activity) {
        // Create a temporary place from check-in metadata
        guard let metadata = activity.metadata else {
            showError("Unable to load place details for this check-in")
            return
        }
        
        // Determine place category
        let categoryString = metadata.placeCategory ?? "other"
        let category = PlaceCategory(rawValue: categoryString) ?? .other
        
        // Create coordinate if we have location data
        var coordinate: CLLocationCoordinate2D?
        if let lat = metadata.latitude, let lng = metadata.longitude {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        
        // Create GeoLocation from coordinate
        var geoLocation: GeoLocation? = nil
        if let coord = coordinate {
            geoLocation = GeoLocation(
                type: "Point",
                coordinates: [coord.longitude, coord.latitude]
            )
        }
        
        // Create a temporary place object
        let tempPlace = Place(
            id: activity.metadata?.placeId ?? UUID().uuidString,
            name: activity.targetName,
            description: nil,
            address: metadata.placeAddress ?? "",
            location: geoLocation,
            website: nil,
            phone: nil,
            googlePlaceId: nil,
            photos: metadata.placePhoto != nil ? [metadata.placePhoto!] : nil,
            videos: nil,
            category: category,
            customCategoryId: nil,
            subcategory: nil,
            rating: nil,
            userRatingsTotal: nil,
            notes: metadata.message,
            privateNotes: nil,
            publicNotes: nil,
            tags: nil,
            reviews: nil,
            openingHours: nil,
            priceLevel: nil,
            likes: nil,
            likesCount: nil,
            commentsCount: 0,
            circleId: metadata.circleId ?? "",
            addedBy: activity.actorId,
            addedByUser: nil,
            privacy: .public,
            createdAt: Date(),
            updatedAt: Date(),
            isNew: true
        )
        
        // Navigate to place detail with the temporary place
        let placeDetailVC = PlaceDetailViewController(place: tempPlace, circle: nil)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
    
    func loadPlaceAndNavigate(placeId: String) {
        // Show loading
        let loadingAlert = UIAlertController(title: "Loading", message: "Loading place...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let place):
                        // We need to find the circle
                        guard let circleId = place.circleId else {
                            let alert = UIAlertController(
                                title: "Error",
                                message: "Place has no associated circle",
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(alert, animated: true)
                            return
                        }
                        CircleService.shared.fetchCircleById(id: circleId) { circleResult in
                            DispatchQueue.main.async {
                                switch circleResult {
                                case .success(let circle):
                                    let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                                    self.navigationController?.pushViewController(placeDetailVC, animated: true)
                                case .failure:
                                    // Show error
                                    let alert = UIAlertController(
                                        title: "Error",
                                        message: "Failed to load place details",
                                        preferredStyle: .alert
                                    )
                                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self.present(alert, animated: true)
                                }
                            }
                        }
                    case .failure(let error):
                        let alert = UIAlertController(
                            title: "Error",
                            message: "Failed to load place: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Swipe Actions for Activity Table
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Only handle swipe actions for activity table
        guard tableView == activityTableView else { return nil }

        // Individual rows only — group summary rows aren't deletable
        guard let activity = singleActivity(at: indexPath.row) else { return nil }
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // Only allow deletion of user's own activities
        guard activity.actorId == currentUserId else { return nil }
        
        // Create delete action
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.confirmDeleteActivity(at: indexPath, completion: completion)
        }
        
        deleteAction.backgroundColor = .systemRed
        deleteAction.image = UIImage(systemName: "trash")
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false // Require confirmation
        
        return configuration
    }
    
    // Helper method to confirm and delete activity
    func confirmDeleteActivity(at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
        guard let activity = singleActivity(at: indexPath.row) else {
            completion(false)
            return
        }
        
        // Show confirmation alert
        let alert = UIAlertController(
            title: "Delete Activity",
            message: "Are you sure you want to delete this activity? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteActivity(activity, at: indexPath, completion: completion)
        })
        
        present(alert, animated: true)
    }
    
    // Method to delete activity from backend and update UI
    func deleteActivity(_ activity: Activity, at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
        // Call API to delete activity
        let endpoint = "activities/\(activity.id)"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .delete
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion(false)
                    return
                }
                
                switch result {
                case .success:
                    // Remove by id and re-derive the grouped rows (row indexes
                    // don't map 1:1 to activities anymore)
                    self.activities.removeAll { $0.id == activity.id }
                    self.updateActivityFeed()
                    
                    // Show success feedback
                    let successAlert = UIAlertController(
                        title: nil,
                        message: "Activity deleted successfully",
                        preferredStyle: .alert
                    )
                    self.present(successAlert, animated: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        successAlert.dismiss(animated: true)
                    }
                    
                    completion(true)
                    
                case .failure(let error):
                    Logger.debug("Failed to delete activity: \(error)")
                    
                    // Show error alert
                    let errorAlert = UIAlertController(
                        title: "Error",
                        message: "Failed to delete activity. Please try again.",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(errorAlert, animated: true)
                    
                    completion(false)
                }
            }
        }
    }
}

