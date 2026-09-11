import UIKit

/// The home screen's Activity tab: the network activity feed
/// (`ActivityService.getNetworkActivities`), paginated by scroll, with
/// same-actor bursts collapsed into expandable group rows, in-place
/// reaction/comment updates, swipe-to-delete for the user's own rows, and
/// the SSE-driven "just the newest" refresh.
///
/// Navigation out of the feed (place, circle, moment, check-in) goes
/// through the host: those destinations depend on the home's loaded
/// circles/places and are shared with deep links.
final class HomeActivityFeedViewController: BaseViewController, HomeContentTab {
    weak var host: HomeContentTabHost?
    var isActiveTab = false

    // Any mutation re-derives the grouped feed rows — several load paths
    // (preload, loader) set `activities` then reload the table directly, and
    // the table renders from `feedItems`.
    var activities: [Activity] = [] {
        didSet {
            regroupActivities()
            // Runs for EVERY load path so the viewport-fill isn't tied to one
            fillViewportIfNeeded()
        }
    }
    private var isLoadingActivities = false

    // Pagination
    private var currentOffset = 0
    private var hasMoreActivities = true
    private var isLoadingMoreActivities = false

    /// A feed row: either one activity, or a burst of activities by the same
    /// actor within an hour, collapsed into a summary row.
    enum FeedItem {
        case single(Activity)
        case group([Activity])
        // An expanded group's member row — rendered indented under its
        // summary header so the burst reads as one nested block
        case groupChild(Activity)
    }

    /// Derived render model for the table. Rebuilt from `activities` in
    /// `regroupActivities()` — never mutated directly.
    private(set) var feedItems: [FeedItem] = []
    /// Groups the user has expanded inline, keyed by the group's first activity id
    private var expandedGroupKeys: Set<String> = []

    /// The activity a long-pressed reaction picker is for
    private var currentReactionActivity: Activity?

    /// Guards against the same moment-open firing twice. A single activity-row
    /// tap can trigger BOTH `tableView(_:didSelectRowAt:)` (→ `navigateToVideo`)
    /// and the cell's content-tap gesture (→ `navigateToVideoFromActivity`),
    /// which otherwise stacks two "Loading video..." alerts and fires two
    /// detail requests. Reset once the open resolves (present or error).
    private var isOpeningMoment = false

    let tableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Constants.Colors.background
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.showsVerticalScrollIndicator = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    private let statusView = HomeTabStatusView()

    /// Table footer shown while the next page loads
    private let loadMoreIndicatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false

        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = Constants.Colors.primary
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()

        view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: 60)
        ])
        return view
    }()

    // The host's segment switch drives loading; nothing loads on its own.
    override var loadsDataOnViewDidLoad: Bool { false }
    override var reloadsDataOnAppear: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        view.addSubview(tableView)
        view.addSubview(statusView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.topAnchor.constraint(equalTo: view.topAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ActivityFeedCell.self, forCellReuseIdentifier: ActivityFeedCell.identifier)

        // Listen for moment deletion to drop its activity rows
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMomentDeleted(_:)),
            name: Notification.Name("MomentDeleted"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - HomeContentTab

    func tabDidBecomeVisible() {
        tableView.isHidden = false
        // Load activities if needed
        if activities.isEmpty {
            fetchActivities()
        }
    }

    func tabWillHide() {}

    func refreshTab() {
        fetchActivities()
    }

    /// Tab-bar Home re-tap: the table scrolls independently of the outer
    /// scroll view, so reset it too when it's on screen.
    func scrollToTop() {
        guard isActiveTab, !tableView.isHidden, tableView.window != nil else { return }
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.contentInset.top), animated: true)
    }

    /// `activities` were set from outside (preload / initial load) — show them.
    func showLoadedActivities() {
        tableView.reloadData()
        statusView.isLoading = false
        statusView.message = nil
    }

    /// Drops every row by `userId` (the user just blocked them); the host
    /// refetches for the server's answer.
    func removeActivities(by userId: String) {
        activities.removeAll { $0.actorId == userId }
        tableView.reloadData()
    }

    // MARK: - Loading

    func fetchActivities(loadMore: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !isLoadingActivities && !isLoadingMoreActivities else {
            Logger.debug("🔄 Already loading activities, skipping...")
            completion?(false)
            return
        }

        // Don't load more if we've reached the end
        if loadMore && !hasMoreActivities {
            Logger.debug("📊 No more activities to load")
            completion?(false)
            return
        }

        Logger.debug("📊 Starting to fetch activities... (loadMore: \(loadMore))")

        // Check if user needs notification prompt when viewing activity feed
        if !loadMore && activities.isEmpty {
            NotificationPromptManager.shared.checkAndPromptIfNeeded(in: self, context: .activityFeed)
        }

        if loadMore {
            isLoadingMoreActivities = true
            tableView.tableFooterView = loadMoreIndicatorView
        } else {
            isLoadingActivities = true
            statusView.isLoading = true

            // Hide the table view while loading initial activities
            if activities.isEmpty {
                tableView.isHidden = true
            }
            currentOffset = 0 // Reset offset for fresh load
            hasMoreActivities = true
        }

        let offset = loadMore ? currentOffset : 0

        ActivityService.shared.getNetworkActivities(limit: 20, offset: offset) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if loadMore {
                    self.isLoadingMoreActivities = false
                } else {
                    self.isLoadingActivities = false
                    self.statusView.isLoading = false
                }

                switch result {
                case .success(let response):
                    Logger.debug("✅ Successfully fetched \(response.activities.count) activities")

                    if loadMore {
                        // Append to existing activities, skipping any already
                        // shown — SSE prepends shift the pagination offset, so
                        // the next page can overlap what's on screen
                        let existingIds = Set(self.activities.map { $0.id })
                        let newActivities = response.activities.filter { !existingIds.contains($0.id) }
                        self.activities.append(contentsOf: newActivities)
                    } else {
                        self.activities = response.activities
                    }

                    // Update pagination state
                    self.currentOffset = self.activities.count
                    self.hasMoreActivities = response.hasMore
                    Logger.debug("📊 Total activities: \(self.activities.count), hasMore: \(response.hasMore)")

                    self.updateActivityFeed()

                case .failure(let error):
                    Logger.debug("❌ Error fetching activities: \(error)")
                    if !loadMore {
                        self.activities = []
                        self.updateActivityFeed()
                    }
                }

                self.host?.endRefreshing()
                completion?(true)
            }
        }
    }

    /// Smart refresh for SSE events: fetch only the newest activities and
    /// merge, so scroll position survives. Also prunes rows deleted
    /// server-side.
    func refreshWithNewItems() {
        // If we don't have any activities yet, do a full load
        if activities.isEmpty {
            fetchActivities()
            return
        }

        ActivityService.shared.getNetworkActivities(limit: 5, offset: 0) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let newActivities = response.activities

                    // Find activities that aren't already in our list
                    let addedActivities = newActivities.filter { activity in
                        !self.activities.contains(where: { $0.id == activity.id })
                    }

                    // Prune rows deleted server-side: anything we hold that's
                    // newer than the oldest fetched activity should have been
                    // in this newest-first fetch — if it wasn't, it's gone
                    // (e.g. the actor swiped their activity away).
                    var removedCount = 0
                    if let oldestFetched = newActivities.last?.timestamp {
                        let fetchedIds = Set(newActivities.map { $0.id })
                        let before = self.activities.count
                        self.activities.removeAll {
                            $0.timestamp > oldestFetched && !fetchedIds.contains($0.id)
                        }
                        removedCount = before - self.activities.count
                    }

                    if !addedActivities.isEmpty || removedCount > 0 {
                        // Insert new activities at the beginning, then go
                        // through the grouped-feed pipeline — a direct
                        // insertRows would desync rows from feedItems
                        self.activities.insert(contentsOf: addedActivities, at: 0)
                        self.updateActivityFeed()
                        Logger.info("SSE feed refresh: +\(addedActivities.count) new, -\(removedCount) stale")
                    }

                case .failure(let error):
                    Logger.error("Failed to fetch new activities via SSE: \(error)")
                }
            }
        }
    }

    func updateActivityFeed() {
        resolveMissingActivityActors()
        regroupActivities()
        isLoadingActivities = false
        statusView.isLoading = false

        // Only show the table if this is the visible tab
        if isActiveTab {
            tableView.isHidden = false
        }

        // Update empty state
        statusView.message = activities.isEmpty ? "No recent activity from your network" : nil

        // Update table footer for loading more
        if isLoadingMoreActivities && hasMoreActivities {
            tableView.tableFooterView = loadMoreIndicatorView
        } else {
            tableView.tableFooterView = nil
        }

        tableView.reloadData()
        host?.layoutContentIfNeeded()
        fillViewportIfNeeded()
    }

    /// Patches actorless feed rows from users the app already knows: the
    /// signed-in user first (your own activity must NEVER render anonymous),
    /// then actors carried by other rows in the same feed. Rows that still
    /// can't be resolved keep actor nil and render name-less rather than
    /// showing a wrong identity.
    private func resolveMissingActivityActors() {
        guard activities.contains(where: { $0.actor == nil }) else { return }

        var knownActors: [String: User] = [:]
        for activity in activities {
            if let actor = activity.actor {
                knownActors[activity.actorId] = actor
            }
        }

        let me = AuthService.shared.currentUser

        activities = activities.map { activity in
            guard activity.actor == nil else { return activity }
            if let me = me, IDNormalizer.isSameUser(activity.actorId, me.id) {
                return activity.withActor(me)
            }
            if let known = knownActors[activity.actorId] {
                return activity.withActor(known)
            }
            return activity
        }
    }

    /// Grouping can collapse an entire fetched page into a single row (e.g. one
    /// actor bulk-adding many places), leaving too few rows to scroll — so the
    /// scroll-triggered load-more never fires and the rest of the history never
    /// loads. Auto-load the next page until there's enough to fill the viewport
    /// (capped so a huge single-actor import can't loop).
    private func fillViewportIfNeeded() {
        guard isActiveTab,
              feedItems.count < 8,
              hasMoreActivities,
              !isLoadingActivities,
              !isLoadingMoreActivities,
              activities.count < 300 else { return }
        // Launch paths populate `activities` without maintaining currentOffset,
        // so anchor the next page to what's actually loaded — otherwise loadMore
        // re-fetches page 1 and dedup drops it, stalling the fill.
        currentOffset = activities.count
        fetchActivities(loadMore: true)
    }

    @objc private func handleMomentDeleted(_ notification: Notification) {
        guard let videoId = notification.userInfo?["videoId"] as? String else { return }
        Logger.debug("📢 Received MomentDeleted notification for video: \(videoId)")

        let before = activities.count
        activities.removeAll { $0.targetType == "place_video" && $0.targetId == videoId }
        guard activities.count < before else { return }
        Logger.debug("✅ Removed \(before - activities.count) activity(ies) for the deleted moment")

        // Rows are derived from the grouped feed, so re-render rather than
        // deleting by index; the hidden table stays in sync with the shrunk
        // data source so it can't crash when shown again
        tableView.reloadData()
        statusView.message = activities.isEmpty ? "No recent activity from your network" : nil
    }

    // MARK: - Grouping

    /// Only check-ins stay ungrouped. Place-adds DO group: a burst of
    /// same-actor adds (e.g. someone importing many places at once) would
    /// otherwise flood the feed — the exact case grouping exists to collapse.
    static func isStandaloneActivity(_ activity: Activity) -> Bool {
        activity.type == .checkIn
    }

    /// Collapses consecutive same-actor activities (rolling 60-minute window)
    /// into groups of ≥2. Standalone rows interleaved in a burst don't break
    /// the surrounding group: the group is inserted back at the position of
    /// its newest member.
    static func group(_ activities: [Activity], expandedKeys: Set<String>) -> [FeedItem] {
        var items: [FeedItem] = []
        var pendingGroup: [Activity] = []
        var pendingStartIndex: Int?

        func flushGroup() {
            guard !pendingGroup.isEmpty else { return }
            let insertAt = min(pendingStartIndex ?? items.count, items.count)
            if pendingGroup.count >= 2 {
                var groupRows: [FeedItem] = [.group(pendingGroup)]
                if expandedKeys.contains(pendingGroup[0].id) {
                    groupRows.append(contentsOf: pendingGroup.map { .groupChild($0) })
                }
                items.insert(contentsOf: groupRows, at: insertAt)
            } else {
                items.insert(.single(pendingGroup[0]), at: insertAt)
            }
            pendingGroup = []
            pendingStartIndex = nil
        }

        for activity in activities {
            if isStandaloneActivity(activity) {
                items.append(.single(activity))
                continue
            }
            if let last = pendingGroup.last {
                // Feed is newest-first: `activity` is older than `last`
                let sameActor = activity.actorId == pendingGroup[0].actorId
                let withinWindow = last.timestamp.timeIntervalSince(activity.timestamp) <= 3600
                if sameActor && withinWindow {
                    pendingGroup.append(activity)
                    continue
                }
                flushGroup()
            }
            pendingStartIndex = items.count
            pendingGroup.append(activity)
        }
        flushGroup()
        return items
    }

    private func regroupActivities() {
        feedItems = Self.group(activities, expandedKeys: expandedGroupKeys)
    }

    private func feedItem(at row: Int) -> FeedItem? {
        row < feedItems.count ? feedItems[row] : nil
    }

    /// The single activity backing a row, or nil for group summary rows
    private func singleActivity(at row: Int) -> Activity? {
        switch feedItem(at: row) {
        case .single(let activity), .groupChild(let activity):
            return activity
        default:
            return nil
        }
    }

    private func toggleActivityGroup(withKey key: String) {
        let expanding = !expandedGroupKeys.contains(key)
        if expanding {
            expandedGroupKeys.insert(key)
        } else {
            expandedGroupKeys.remove(key)
        }

        // Animate the member rows in/out under their header so it's obvious
        // what the tap revealed (vs. the untouched rows below the group)
        let itemsBefore = feedItems
        regroupActivities()
        func headerIndex(in items: [FeedItem]) -> Int? {
            items.firstIndex {
                if case .group(let g) = $0 { return g.first?.id == key }
                return false
            }
        }
        guard let header = headerIndex(in: feedItems),
              headerIndex(in: itemsBefore) == header,
              case .group(let group) = feedItems[header] else {
            tableView.reloadData()
            return
        }
        let childPaths = (1...group.count).map { IndexPath(row: header + $0, section: 0) }
        tableView.performBatchUpdates {
            if expanding {
                tableView.insertRows(at: childPaths, with: .fade)
            } else {
                tableView.deleteRows(at: childPaths, with: .fade)
            }
        }
        // Refresh the header's "Show all / Show less" state
        tableView.reloadRows(at: [IndexPath(row: header, section: 0)], with: .none)
    }

    // MARK: - In-place row updates

    /// Drops a feed row whose backing activity no longer exists server-side
    private func removeStaleActivity(id: String) {
        guard activities.contains(where: { $0.id == id }) else { return }
        activities.removeAll { $0.id == id }
        tableView.reloadData()
    }

    /// Applies a reaction toggle to the in-memory feed and reloads the table
    /// without touching scroll position; the next natural feed load brings
    /// the server-computed counts.
    private func applyLocalReaction(activityId: String, emoji: String?) {
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
        tableView.reloadData()
    }

    // MARK: - Moment navigation

    /// Fetch the moment, then drop into the inline Moments tab on it. Shared
    /// by the row tap, the cell's content tap and deep links, so one in-flight
    /// guard covers all three.
    func navigateToVideo(withId videoId: String, showsLoading: Bool) {
        // A blank id would hit `GET /videos/` → server 500; a duplicate tap
        // would double-open.
        guard !videoId.isEmpty, !isOpeningMoment else { return }
        isOpeningMoment = true

        let loadingAlert = showsLoading ? AlertPresenter.showLoading(message: "Loading video...", from: self) : nil

        APIService.shared.request(
            endpoint: "videos/\(videoId)",
            method: .get
        ) { [weak self] (result: Result<PlaceVideoResponse, APIError>) in
            DispatchQueue.main.async {
                let finish = {
                    guard let self = self else { return }
                    self.isOpeningMoment = false
                    switch result {
                    case .success(let response):
                        self.host?.openMomentInMomentsTab(response.data)
                    case .failure(let error):
                        // Prefer the server's friendly, actionable message (e.g.
                        // "You're not connected to X. Send them a connection
                        // request to view this moment.") over a generic string.
                        self.showError(error.serverMessage ?? "Unable to load this moment. Please try again.")
                    }
                }
                if let loadingAlert = loadingAlert {
                    loadingAlert.dismiss(animated: true, completion: finish)
                } else {
                    finish()
                }
            }
        }
    }

    private func navigateToPlaceFromActivity(_ activity: Activity) {
        // For video uploads and check-ins the place is in metadata; otherwise it's the target
        let placeId: String
        if activity.type == .videoUploaded || activity.type == .checkIn {
            placeId = activity.metadata?.placeId ?? ""
        } else {
            placeId = activity.targetId
        }
        guard !placeId.isEmpty else { return }

        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] (result: Result<Place, Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let place):
                    let detailVC = PlaceDetailViewController(place: place)
                    self?.navigationController?.pushViewController(detailVC, animated: true)
                case .failure(let error):
                    Logger.error("❌ Failed to fetch place \(placeId): \(error.localizedDescription)")
                    // Not in any circle we can read (likely): for check-ins and
                    // moments, show a limited place view built from the metadata
                    if activity.type == .checkIn || activity.type == .videoUploaded {
                        let tempPlaceVC = TempPlaceDetailViewController()
                        tempPlaceVC.configure(
                            placeId: placeId,
                            name: activity.targetName,
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

    // MARK: - Delete

    private func confirmDeleteActivity(at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
        guard let activity = singleActivity(at: indexPath.row) else {
            completion(false)
            return
        }
        AlertPresenter.showConfirmation(
            title: "Delete Activity",
            message: "Are you sure you want to delete this activity? This action cannot be undone.",
            confirmTitle: "Delete",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in self?.deleteActivity(activity, completion: completion) },
            onCancel: { completion(false) }
        )
    }

    private func deleteActivity(_ activity: Activity, completion: @escaping (Bool) -> Void) {
        APIService.shared.request(
            endpoint: "activities/\(activity.id)",
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
                    // don't map 1:1 to activities)
                    self.activities.removeAll { $0.id == activity.id }
                    self.updateActivityFeed()
                    AlertPresenter.showBriefMessage("Activity deleted successfully", from: self)
                    completion(true)
                case .failure(let error):
                    Logger.debug("Failed to delete activity: \(error)")
                    self.showError("Failed to delete activity. Please try again.")
                    completion(false)
                }
            }
        }
    }
}

// MARK: - Table

extension HomeActivityFeedViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        feedItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ActivityFeedCell.identifier, for: indexPath) as! ActivityFeedCell
        guard let item = feedItem(at: indexPath.row) else { return cell }

        cell.delegate = self
        switch item {
        case .single(let activity):
            cell.configure(with: activity)
            cell.setGroupChildStyle(false)
        case .groupChild(let activity):
            cell.configure(with: activity)
            cell.setGroupChildStyle(true)
        case .group(let groupActivities):
            cell.configure(withGroup: groupActivities,
                           isExpanded: expandedGroupKeys.contains(groupActivities[0].id))
            cell.setGroupChildStyle(false)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = feedItem(at: indexPath.row) else { return }

        // Group summary rows expand/collapse in place
        let activity: Activity
        switch item {
        case .single(let a), .groupChild(let a):
            activity = a
        case .group(let groupActivities):
            toggleActivityGroup(withKey: groupActivities[0].id)
            return
        }

        // Navigate based on activity type
        switch activity.type {
        case .placeAdded, .placeLiked, .photoUploaded, .placeDiscovered:
            host?.navigateToPlace(withId: activity.targetId, showComments: false)
        case .placeCommented:
            // A comment activity lands IN the comments, not at the page top
            host?.navigateToPlace(withId: activity.targetId, showComments: true)
        case .commentLiked:
            // targetId is the COMMENT id for these; the place lives in metadata
            if let placeId = activity.metadata?.placeId {
                host?.navigateToPlace(withId: placeId, showComments: true)
            } else if let globalPlaceId = activity.metadata?.globalPlaceId {
                host?.navigateToGlobalPlace(withId: globalPlaceId, showComments: true)
            }
        case .circleCreated, .circleLiked, .circleCommented:
            host?.navigateToCircle(withId: activity.targetId)
        case .checkIn:
            host?.navigateToCheckInPlace(activity: activity)
        case .videoUploaded, .videoLiked:
            // targetId is the video id for video activities
            navigateToVideo(withId: activity.targetId, showsLoading: true)
        case .commentAdded:
            // Target varies (place, circle, moment) - only navigate when it's a known kind
            if activity.targetType == "circle" {
                host?.navigateToCircle(withId: activity.targetId)
            } else if activity.targetType == "place" {
                host?.navigateToPlace(withId: activity.targetId, showComments: false)
            }
        case .venueAnnouncement, .venueOffer:
            // targetId is the venue's canonical globalPlaces id — open the
            // place page the same way the Specials tab does
            host?.navigateToGlobalPlace(withId: activity.targetId, showComments: false)
        case .globalPlaceLiked:
            // A photo like: targetId is the PHOTO id — the venue is
            // metadata.globalPlaceId (backfilled onto older activities)
            if let globalPlaceId = activity.metadata?.globalPlaceId {
                host?.navigateToGlobalPlace(withId: globalPlaceId, showComments: false)
            }
        case .suggestionSent, .suggestionAccepted,
             .profileUpdated, .userActivity, .reactionAdded, .unknown:
            // No reliable local destination for these
            break
        }
    }

    // Swipe-to-delete the user's own individual rows (group summaries aren't deletable)
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let activity = singleActivity(at: indexPath.row) else { return nil }
        let currentUserId = AuthService.shared.getUserId() ?? ""
        guard activity.actorId == currentUserId else { return nil }

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.confirmDeleteActivity(at: indexPath, completion: completion)
        }
        deleteAction.backgroundColor = .systemRed
        deleteAction.image = UIImage(systemName: "trash")

        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false // Require confirmation
        return configuration
    }

    // Pagination: load the next page near the bottom
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let scrollViewHeight = scrollView.frame.height

        // Within 100 points of the bottom
        if offsetY > contentHeight - scrollViewHeight - 100 {
            if !activities.isEmpty && hasMoreActivities && !isLoadingMoreActivities {
                Logger.debug("📊 Reached bottom of activity table, loading more...")
                fetchActivities(loadMore: true)
            }
        }
    }
}

// MARK: - ActivityFeedCellDelegate

extension HomeActivityFeedViewController: ActivityFeedCellDelegate {
    func didTapUserProfile(user: User) {
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }

    func didTapActivityContent(activity: Activity) {
        switch activity.type {
        case .videoUploaded, .videoLiked:
            // targetId is the video id in both cases
            navigateToVideo(withId: activity.targetId, showsLoading: false)
        case .placeAdded, .placeLiked, .checkIn:
            navigateToPlaceFromActivity(activity)
        case .placeCommented:
            // A comment activity lands IN the comments
            host?.navigateToPlace(withId: activity.targetId, showComments: true)
        case .commentLiked:
            // targetId is the COMMENT id; the place lives in metadata. The
            // cell's content-area gesture covers nearly the whole row, so this
            // must navigate — only margin taps reach the row-level handler.
            if let placeId = activity.metadata?.placeId {
                host?.navigateToPlace(withId: placeId, showComments: true)
            } else if let globalPlaceId = activity.metadata?.globalPlaceId {
                host?.navigateToGlobalPlace(withId: globalPlaceId, showComments: true)
            }
        case .globalPlaceLiked:
            // A photo like: targetId is the PHOTO id, not a place — the venue
            // is metadata.globalPlaceId (backfilled onto older activities)
            if let globalPlaceId = activity.metadata?.globalPlaceId {
                host?.navigateToGlobalPlace(withId: globalPlaceId, showComments: false)
            }
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
        switch activity.type {
        case .videoUploaded, .videoLiked:
            // The thumbnail on a moment activity is the moment itself — open the
            // player, not a place lookup (which 404s: these have no place detail).
            navigateToVideo(withId: activity.targetId, showsLoading: false)
        case .commentLiked:
            // targetId is the comment id, not a place — lookup would 404
            if let placeId = activity.metadata?.placeId {
                host?.navigateToPlace(withId: placeId, showComments: true)
            } else if let globalPlaceId = activity.metadata?.globalPlaceId {
                host?.navigateToGlobalPlace(withId: globalPlaceId, showComments: true)
            }
        case .globalPlaceLiked:
            // targetId is the photo id, not a place — lookup would 404
            if let globalPlaceId = activity.metadata?.globalPlaceId {
                host?.navigateToGlobalPlace(withId: globalPlaceId, showComments: false)
            }
        default:
            navigateToPlaceFromActivity(activity)
        }
    }

    func didTapReactions(activity: Activity) {
        // Unified engagement view (LinkedIn-style)
        let engagementVC = ActivityEngagementViewController(activity: activity)
        let navController = UINavigationController(rootViewController: engagementVC)
        present(navController, animated: true)
    }

    func didTapComments(activity: Activity) {
        let commentsVC = ActivityCommentsViewController(activity: activity)
        commentsVC.onCommentsUpdated = { [weak self] commentCount in
            // Update the row in place — a full refresh would jump the user
            // back to the top of the feed when they close the comments sheet
            guard let self = self,
                  let index = self.activities.firstIndex(where: { $0.id == activity.id }) else { return }
            self.activities[index] = self.activities[index].withCommentCount(commentCount)
            self.tableView.reloadData()
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
        // Toggle: same emoji again removes it, anything else adds/switches
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

    func didLongPressReactionButton(activity: Activity, sourceView: UIView) {
        let reactionPicker = ReactionPickerView()
        reactionPicker.delegate = self
        reactionPicker.translatesAutoresizingMaskIntoConstraints = false

        // The picker dims and captures the whole screen, so it lives on the
        // home's view rather than this tab's 600pt slot
        host?.attachFullScreenOverlay(reactionPicker)

        currentReactionActivity = activity
        reactionPicker.show(from: sourceView)
    }
}

// MARK: - ReactionPickerDelegate

extension HomeActivityFeedViewController: ReactionPickerDelegate {
    func reactionPicker(_ picker: ReactionPickerView, didSelectReaction reaction: ReactionStyle) {
        guard let activity = currentReactionActivity else { return }
        didTapReactionButton(activity: activity, emoji: reaction.rawValue)
        currentReactionActivity = nil
    }

    func reactionPickerDidDismiss(_ picker: ReactionPickerView) {
        currentReactionActivity = nil
    }
}
