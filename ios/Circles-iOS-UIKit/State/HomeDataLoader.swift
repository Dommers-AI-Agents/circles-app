import Foundation
import MapKit

/// What the loader needs from the home screen while data arrives. Every
/// method is a UI side effect the loading code used to perform inline; the
/// loader calls them at exactly the same points in the same sequence, so
/// the timing invariants (loading UI, "no places" banner hold, map
/// refreshes) are unchanged from when this lived on the controller.
protocol HomeDataLoaderDelegate: AnyObject {
    // Loading UI
    func showLoadingState()
    func hideLoadingState()
    func showMapLoadingState()
    func hideMapLoadingState()
    func updateEmptyState()
    func refreshUserList()

    // Feed (the initial load fetches activities/moments alongside circles)
    func loaderDidLoadFeed(activities: [Activity], reels: [PlaceVideo])
    func updateActivityFeed()

    // Map presentation
    func applyFiltersToPlaces(_ places: [Place]) -> [Place]
    func mapRefreshDidFilter(_ places: [Place])
    /// Mirror `places` for the empty state, put them on the embedded map and
    /// update the count pill; optionally re-frame the map shortly after.
    func presentFilteredPlaces(_ places: [Place], adjustRegionAfterDelay: Bool)
    func updateAvailableCategories()
    func updateMapWhenReady()
    func updateMapProgressively(with places: [Place], isFromCache: Bool)
    func refreshMapDisplay(adjustRegion: Bool)
    var embeddedMapViewController: FullScreenMapViewController? { get }

    // Connection scoping
    /// The server resolved a tapped connection id to its canonical user id;
    /// the map/people-row selection must follow it.
    func connectionIdWasCanonicalized(_ canonicalId: String)
    func finishConnectionFetch(_ connectionId: String)
}

/// Loads the home screen's circles and places into a `HomeState` and owns
/// the in-flight flags. The controller keeps the presentation; it forwards
/// its old `fetch*` methods and loading flags here so call sites read the
/// same as before (Phase 4 step 3 of the modularization plan).
final class HomeDataLoader {
    let state: HomeState
    weak var delegate: HomeDataLoaderDelegate?

    /// Cross-instance: has ANY home instance loaded data this app session.
    static var hasLoadedInitialData = false

    var isLoadingCircles = false
    var isLoadingPlaces = false
    var isPerformingInitialLoad = false
    /// Map data is ready to be displayed (set once places have landed).
    var isMapDataReady = false
    /// Instance flag to prevent multiple loads in the same instance.
    var hasStartedLoading = false
    var isFetchingViewport = false

    init(state: HomeState) {
        self.state = state
    }

    // MARK: - Initial load

    /// Unified method to load circles, places, activities and moments.
    func performInitialDataLoad() {
        Logger.debug("🚀 Starting OPTIMIZED initial data load")
        let startTime = CFAbsoluteTimeGetCurrent()

        // Ensure connections are loaded in NetworkManager
        NetworkManager.shared.loadConnections()
        // ...and the followed-users roster, which feeds the map's people filter
        // AND the default "Everyone" scope. Refresh the map once it lands so
        // followed users' pins aren't dropped on the first paint.
        NetworkManager.shared.loadFollowingUsers { [weak self] in
            guard let self = self, self.state.selectedConnectionId == nil else { return }
            self.delegate?.refreshMapDisplay(adjustRegion: false)
        }

        // Show loading state once if not already showing and no cached data
        if !state.isCacheValid {
            delegate?.showLoadingState()
            delegate?.showMapLoadingState()
        }

        // Load all data in parallel for better performance
        let group = DispatchGroup()

        var myCirclesResult: [Circle] = []
        var networkCirclesResult: [Circle] = []
        var activitiesResult: [Activity] = []
        var reelsResult: [PlaceVideo] = []

        // 1. Load my circles
        group.enter()
        CircleService.shared.fetchUserCircles { result in
            switch result {
            case .success(let circles):
                myCirclesResult = circles
                Logger.debug("✅ Fetched \(circles.count) user circles")
            case .failure(let error):
                Logger.debug("❌ Failed to fetch user circles: \(error)")
            }
            group.leave()
        }

        // 2. Load network circles (parallel)
        group.enter()
        APIService.shared.request(
            endpoint: "network/my-network-circles",
            method: .get,
            requiresAuth: true
        ) { (result: Result<CirclesDataResponse, APIError>) in
            switch result {
            case .success(let response):
                networkCirclesResult = response.data
                Logger.debug("✅ Fetched \(response.data.count) network circles")
            case .failure(let error):
                Logger.debug("❌ Failed to fetch network circles: \(error)")
            }
            group.leave()
        }

        // 3. Load activities (parallel)
        group.enter()
        ActivityService.shared.getNetworkActivities(limit: 20, offset: 0) { result in
            switch result {
            case .success(let response):
                activitiesResult = response.activities
                Logger.debug("✅ Fetched \(response.activities.count) activities")
            case .failure(let error):
                Logger.debug("❌ Failed to fetch activities: \(error)")
            }
            group.leave()
        }

        // 4. Load initial moments/reels (parallel)
        group.enter()
        APIService.shared.request(
            endpoint: "videos/reels/feed?limit=20&offset=0",
            method: .get,
            requiresAuth: true
        ) { (result: Result<VideosResponse, APIError>) in
            switch result {
            case .success(let response):
                reelsResult = response.data
                Logger.debug("✅ Fetched \(reelsResult.count) moments")
            case .failure(let error):
                Logger.debug("❌ Failed to fetch moments: \(error)")
            }
            group.leave()
        }

        // First phase completion - process circles, activities, and moments
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            self.state.circles = myCirclesResult
            self.state.networkCircles = networkCirclesResult
            self.delegate?.loaderDidLoadFeed(activities: activitiesResult, reels: reelsResult)

            let circleLoadTime = CFAbsoluteTimeGetCurrent() - startTime
            Logger.debug("⏱️ Phase 1 completed in \(String(format: "%.2f", circleLoadTime)) seconds")

            self.delegate?.updateEmptyState()
            self.delegate?.updateActivityFeed()

            // Now fetch places from all circles in parallel.
            // With viewport loading, network circle places arrive on demand for the
            // visible map region instead — only own circles are fan-out fetched.
            let allCircles = myCirclesResult
            guard !allCircles.isEmpty else {
                self.isMapDataReady = true
                self.delegate?.updateMapWhenReady()
                self.isLoadingPlaces = false
                self.isPerformingInitialLoad = false
                self.delegate?.hideLoadingState()
                self.delegate?.refreshUserList()

                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                Logger.debug("✅ OPTIMIZED load completed in \(String(format: "%.2f", totalTime)) seconds (no circles)")
                return
            }

            // Phase 2: Fetch places — one POST places/batch per 50 circle ids
            let placeGroup = DispatchGroup()
            var placesArray = [[Place]]()
            let placesLock = NSLock()
            var placesFetchComplete = true

            let circleIdsToFetch = allCircles.map { $0.id }
            var chunkStart = 0
            while chunkStart < circleIdsToFetch.count {
                let chunk = Array(circleIdsToFetch[chunkStart..<min(chunkStart + 50, circleIdsToFetch.count)])
                chunkStart += 50
                placeGroup.enter()
                PlaceService.shared.fetchPlacesByMultipleCircles(circleIds: chunk) { result in
                    switch result {
                    case .success(let places):
                        placesLock.lock()
                        placesArray.append(places)
                        placesLock.unlock()
                        Logger.debug("✅ Batch fetched \(places.count) places from \(chunk.count) circles")
                    case .failure(let error):
                        Logger.debug("❌ Batch place fetch failed: \(error)")
                        placesFetchComplete = false
                    }
                    placeGroup.leave()
                }
            }

            placeGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }

                // Final deduplication and data integrity check
                let uniquePlaces = HomeState.dedupe(placesArray.flatMap { $0 })
                self.state.allPlaces = uniquePlaces

                // Update available categories now that we have all places
                self.delegate?.updateAvailableCategories()

                // Extract user's own places
                let userCircleIds = Set(myCirclesResult.map { $0.id })
                self.state.userOwnPlaces = uniquePlaces.filter { place in
                    if let circleId = place.circleId {
                        return userCircleIds.contains(circleId)
                    }
                    return false
                }

                // Cache the final places data
                self.state.cache(uniquePlaces)

                // Persist own places for the next cold start's instant paint —
                // only from a COMPLETE fetch (partial sets must never hit disk)
                if placesFetchComplete, !self.state.userOwnPlaces.isEmpty,
                   let cacheUserId = AuthService.shared.getUserId() {
                    PlacesDiskCache.shared.save(places: self.state.userOwnPlaces, userId: cacheUserId)
                }

                // Final map update with complete data
                self.isMapDataReady = true
                let finalPlaces = self.delegate?.applyFiltersToPlaces(uniquePlaces) ?? []
                self.delegate?.presentFilteredPlaces(finalPlaces, adjustRegionAfterDelay: true)

                // Hide loading state - places are fully loaded
                self.delegate?.hideMapLoadingState()

                // Final cleanup
                self.isLoadingPlaces = false
                self.isPerformingInitialLoad = false
                self.delegate?.hideLoadingState()
                self.delegate?.refreshUserList()
                HomeDataLoader.hasLoadedInitialData = true

                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                Logger.debug("✅ OPTIMIZED load completed in \(String(format: "%.2f", totalTime)) seconds")
                Logger.debug("   - My circles: \(myCirclesResult.count)")
                Logger.debug("   - Network circles: \(networkCirclesResult.count)")
                Logger.debug("   - Total places: \(uniquePlaces.count)")
                Logger.debug("   - Activities: \(activitiesResult.count)")
                Logger.debug("   - Moments: \(reelsResult.count)")
            }
        }
    }

    // MARK: - Circles

    func fetchCircles(completion: (() -> Void)? = nil) {
        isLoadingCircles = true

        CircleService.shared.fetchUserCircles { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoadingCircles = false

                switch result {
                case .success(let circles):
                    Logger.debug("✅ Successfully fetched \(circles.count) user circles")
                    self.state.circles = circles
                    self.fetchAllPlacesFromCircles()
                    completion?()
                    // Don't mark as loaded here - wait until places are fetched
                case .failure(let error):
                    Logger.debug("❌ Error fetching circles: \(error.localizedDescription)")
                    completion?()

                    // If it's a duplicate request error, still need to clean up state
                    if case .duplicateRequest = error as? APIError {
                        Logger.debug("❌ Duplicate request detected - cleaning up state")
                        self.isLoadingCircles = false
                        self.isPerformingInitialLoad = false
                        self.delegate?.hideLoadingState()
                        self.delegate?.hideMapLoadingState()
                        return
                    }

                    // Show empty state instead of sample circles
                    self.state.circles = []
                    self.state.allPlaces = []
                    self.state.userOwnPlaces = []
                    self.isLoadingCircles = false
                    self.isPerformingInitialLoad = false
                    self.delegate?.hideLoadingState()
                    self.delegate?.hideMapLoadingState()
                }

                self.delegate?.updateEmptyState()
            }
        }
    }

    func fetchNetworkCircles(completion: (() -> Void)? = nil) {
        APIService.shared.request(
            endpoint: "network/my-network-circles",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<CirclesDataResponse, APIError>) in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    Logger.debug("✅ Successfully fetched \(response.data.count) network circles")
                    let currentUserId = AuthService.shared.getUserId() ?? ""
                    for circle in response.data where IDNormalizer.isSameUser(circle.owner, currentUserId) {
                        Logger.debug("⚠️ WARNING: Network circles contains user's own circle: \(circle.name) (owner \(circle.owner), me \(currentUserId))")
                    }
                    self.state.networkCircles = response.data
                    self.delegate?.updateEmptyState()
                    completion?()
                case .failure(let error):
                    Logger.debug("❌ Error fetching network circles: \(error.localizedDescription)")
                    completion?()

                    // If it's a duplicate request error, just ignore it
                    if case .duplicateRequest = error {
                        return
                    }

                    self.state.networkCircles = []
                    self.delegate?.updateEmptyState()
                }
            }
        }
    }

    // MARK: - Places

    /// Instant pins: paint the last session's complete place set from disk
    /// while the network refresh runs. Strictly stale-while-revalidate — the
    /// in-flight fetch REPLACES this set wholesale when it lands, so deleted
    /// or edited places disappear after one refresh. Never blocks, never
    /// merges, and only paints when nothing fresher is already on screen.
    func paintPlacesFromDiskCacheIfEmpty() {
        guard !state.hasPaintedPlacesFromDiskCache, state.allPlaces.isEmpty,
              let userId = AuthService.shared.getUserId() else { return }
        state.hasPaintedPlacesFromDiskCache = true

        PlacesDiskCache.shared.load(userId: userId) { [weak self] cached in
            guard let self = self, let cached = cached, !cached.isEmpty else { return }
            // A network result may have landed while the disk read ran — it wins.
            guard self.state.allPlaces.isEmpty else { return }

            Logger.debug("💾 Painting \(cached.count) cached places while refresh is in flight")
            self.state.allPlaces = cached
            let userCircleIds = self.state.ownCircleIds
            if !userCircleIds.isEmpty {
                self.state.userOwnPlaces = cached.filter { place in
                    guard let circleId = place.circleId else { return false }
                    return userCircleIds.contains(circleId)
                }
            }
            self.isMapDataReady = true
            let filtered = self.delegate?.applyFiltersToPlaces(cached) ?? []
            self.delegate?.presentFilteredPlaces(filtered, adjustRegionAfterDelay: false)
            self.delegate?.updateAvailableCategories()
            self.delegate?.hideMapLoadingState()
        }
    }

    /// Fetches every place in the user's own circles (network circle places
    /// arrive per visible map region — see `fetchViewportPlaces`). The cache
    /// is deliberately NOT consulted here: a partial cached set once served
    /// stale-missing places, so own places are always refetched in full.
    func fetchAllPlacesFromCircles() {
        // Reset map data ready flag at the start of any fetch
        isMapDataReady = false

        Logger.debug("📍 fetchAllPlacesFromCircles() - user circles: \(state.circles.count), network circles: \(state.networkCircles.count)")

        var allFetchedPlaces: [Place] = []
        let group = DispatchGroup()

        // Show loading state for places and reset map data ready flag
        isLoadingPlaces = true
        isMapDataReady = false

        // Loading state is already shown by performInitialDataLoad, don't show again

        // If no circles at all, just update UI and return
        if state.circles.isEmpty && state.networkCircles.isEmpty {
            Logger.debug("📍 No circles to fetch places from")
            state.allPlaces = []
            state.userOwnPlaces = []
            delegate?.mapRefreshDidFilter([])

            // Mark data as ready (empty) and update map
            isMapDataReady = true
            delegate?.updateMapWhenReady()

            isLoadingPlaces = false
            isPerformingInitialLoad = false
            delegate?.hideLoadingState()
            // Don't set hasLoadedInitialData here - we have no data
            return
        }

        // Fetch user's own places
        var userPlacesCount = 0
        // Tracks whether every own-place request succeeded — the disk cache is
        // only written from a COMPLETE set (a partial one served stale-missing
        // places when the old cache was enabled; that's why it was disabled).
        var ownPlacesFetchComplete = true

        // One POST places/batch instead of one GET per circle (server caps
        // a request at 50 circle ids; typically this is a single request)
        let ownCircleIds = state.circles.map { $0.id }
        Logger.debug("📍 Batch-fetching places from \(ownCircleIds.count) user circles")
        var index = 0
        while index < ownCircleIds.count {
            let chunk = Array(ownCircleIds[index..<min(index + 50, ownCircleIds.count)])
            index += 50
            group.enter()
            PlaceService.shared.fetchPlacesByMultipleCircles(circleIds: chunk) { result in
                switch result {
                case .success(let places):
                    Logger.debug("✅ Batch fetched \(places.count) places from \(chunk.count) circles")
                    userPlacesCount += places.count
                    allFetchedPlaces.append(contentsOf: places)
                case .failure(let error):
                    Logger.debug("❌ Batch place fetch failed: \(error)")
                    ownPlacesFetchComplete = false
                }
                group.leave()
            }
        }

        // Always fetch network circles for map view (need to show connection places)
        if state.networkCircles.isEmpty && !state.circles.isEmpty {
            group.enter()
            APIService.shared.request(
                endpoint: "network/my-network-circles",
                method: .get,
                requiresAuth: true
            ) { [weak self] (result: Result<CirclesDataResponse, APIError>) in
                switch result {
                case .success(let response):
                    self?.state.networkCircles = response.data
                    // Their places arrive per visible map region (viewport loading)
                case .failure(let error):
                    Logger.debug("Failed to fetch network circles: \(error)")
                    // If it's a duplicate request error, retry
                    if case .duplicateRequest = error {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self?.fetchNetworkCircles()
                        }
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main, execute: { [weak self] in
            guard let self = self else { return }

            Logger.debug("📍 PLACE FETCH COMPLETE: \(allFetchedPlaces.count) raw places (\(userPlacesCount) own), \(self.state.circles.count) user circles, \(self.state.networkCircles.count) network circles")

            // Deduplicate places that might exist in multiple circles
            let deduplicatedPlaces = self.removeDuplicatePlaces(allFetchedPlaces)
            self.state.allPlaces = deduplicatedPlaces

            // Own places = in my circles, or in a circle I own that arrived via
            // the network list (in case circle ids don't line up)
            let currentUserId = AuthService.shared.getUserId() ?? ""
            let userCircleIds = self.state.ownCircleIds
            let userPlacesAfterDedup = deduplicatedPlaces.filter { place in
                if let circleId = place.circleId, userCircleIds.contains(circleId) {
                    return true
                }
                if let circleId = place.circleId, let circle = self.state.networkCircles.first(where: { $0.id == circleId }) {
                    return IDNormalizer.isSameUser(circle.owner, currentUserId)
                }
                return false
            }
            Logger.debug("📍 After deduplication: \(userPlacesAfterDedup.count) own places, \(deduplicatedPlaces.count) total unique")

            // Store user's own places separately for search filtering
            self.state.userOwnPlaces = userPlacesAfterDedup

            // Cache the deduplicated places with expiry time
            self.state.cache(deduplicatedPlaces)

            // Persist the user's own places for the next cold start's instant
            // paint — ONLY when every own-place request succeeded (a partial
            // set on disk is exactly the bug that got the old cache disabled)
            if ownPlacesFetchComplete, !userPlacesAfterDedup.isEmpty,
               let cacheUserId = AuthService.shared.getUserId() {
                PlacesDiskCache.shared.save(places: userPlacesAfterDedup, userId: cacheUserId)
            }

            // Apply filtering to fetched places. Unlocated places (unresolved
            // imports) are deliberately NOT surfaced on the map — the import
            // resolver works through them in the background.
            let mapFilteredPlaces = self.delegate?.applyFiltersToPlaces(deduplicatedPlaces) ?? []
            let placesWithLocation = mapFilteredPlaces.filter { $0.location?.clLocation != nil }.count
            Logger.debug("📍 Map update: \(mapFilteredPlaces.count) filtered places, \(placesWithLocation) with location")

            // Mirror for UI consistency (empty states) — guarded during search
            self.delegate?.mapRefreshDidFilter(mapFilteredPlaces)

            // Use progressive loading instead of waiting for everything
            self.delegate?.updateMapProgressively(with: deduplicatedPlaces, isFromCache: false)

            // Hide loading state
            self.isLoadingPlaces = false
            self.isPerformingInitialLoad = false // Reset initial load flag
            self.delegate?.hideLoadingState()

            // With viewport loading, re-fetch network places for the current
            // region so refresh paths (place added/edited) pick up changes
            if let mapVC = self.delegate?.embeddedMapViewController {
                self.state.fetchedViewportCircles.removeAll()
                self.fetchViewportPlaces(region: mapVC.currentRegion, for: mapVC)
            }

            // Mark that we've loaded data only if we actually have data
            if !self.state.circles.isEmpty || !allFetchedPlaces.isEmpty {
                HomeDataLoader.hasLoadedInitialData = true
            }
        })
    }

    // MARK: - Viewport-based network places

    /// Fetches network places for the visible map region and merges them into
    /// `allPlaces`. Called (debounced) whenever the map's visible region changes.
    func fetchViewportPlaces(region: MKCoordinateRegion, for controller: FullScreenMapViewController) {
        // Region → covering circle: half the bounding-box diagonal, +10% pad
        let latMeters = region.span.latitudeDelta * 111_320.0
        let lngMeters = region.span.longitudeDelta * 111_320.0 * cos(region.center.latitude * .pi / 180)
        var radiusM = ((latMeters * latMeters + lngMeters * lngMeters).squareRoot() / 2) * 1.1
        radiusM = min(max(radiusM, 100), 100_000) // match server clamp

        // Skip if an earlier fetch already fully covered this area
        if state.isViewportCovered(center: region.center, radiusM: radiusM) {
            Logger.debug("🗺️ [Viewport] Region already covered, skipping fetch")
            return
        }

        guard !isFetchingViewport else { return }
        isFetchingViewport = true

        let requestLimit = 200
        Logger.debug("🗺️ [Viewport] Fetching places: center=(\(region.center.latitude), \(region.center.longitude)) radius=\(Int(radiusM))m")

        PlaceService.shared.fetchNetworkPlacesInViewport(
            centerLat: region.center.latitude,
            centerLng: region.center.longitude,
            radiusM: radiusM,
            limit: requestLimit
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetchingViewport = false

                switch result {
                case .success(let places):
                    Logger.debug("🗺️ [Viewport] Received \(places.count) places")

                    // Record coverage only when the result wasn't truncated by the limit
                    if places.count < requestLimit {
                        self.state.recordFetchedViewport(center: region.center, radiusM: radiusM)
                    }

                    guard !places.isEmpty else { return }

                    // Merge (never replace) so nothing already loaded disappears
                    let countBefore = self.state.allPlaces.count
                    self.state.allPlaces = self.removeDuplicatePlaces(self.state.allPlaces + places)
                    guard self.state.allPlaces.count > countBefore else { return }

                    self.state.cache(self.state.allPlaces)
                    self.delegate?.updateAvailableCategories()

                    // Refresh pins without moving the map (prevents a fetch
                    // loop). This also pushes the unfiltered set to the
                    // presented full map, which filters for itself.
                    self.delegate?.refreshMapDisplay(adjustRegion: false)
                case .failure(let error):
                    // Non-fatal: a later pan retries the fetch
                    Logger.debug("🗺️ [Viewport] Fetch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Per-connection places

    /// Fetches ALL places for one connection (not viewport-bounded) so the map
    /// can zoom to their places when they're selected as the filter.
    /// Uses the same user-circles + per-circle path as the profile map — the
    /// places/batch endpoint re-checks connections by exact id and can silently
    /// drop circles when connection docs and circle owners use different id formats.
    func fetchAllPlacesForConnection(_ connectionId: String) {
        Logger.debug("📍 Fetching circles for connection \(connectionId)")
        APIService.shared.request(
            endpoint: "network/user-circles/\(connectionId)",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UserCirclesResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    let connectionCircles = response.data.circles
                    // Register these circles so the connection/category filters
                    // and owner mapping recognize their places
                    let knownIds = Set(self.state.networkCircles.map { $0.id })
                    self.state.networkCircles.append(contentsOf: connectionCircles.filter { !knownIds.contains($0.id) })

                    // Adopt the canonical user id the endpoint resolved, so the
                    // owner-matching filter lines up with these circles' owner
                    let canonicalId = response.data.user.id
                    if self.state.selectedConnectionId == connectionId && canonicalId != connectionId {
                        self.state.selectedConnectionId = canonicalId
                        self.delegate?.connectionIdWasCanonicalized(canonicalId)
                    }

                    // The endpoint already embeds each circle's places - use them
                    // directly instead of refetching one request per circle
                    let embeddedPlaces = connectionCircles.flatMap { $0.placesWithDetails ?? [] }
                    if !embeddedPlaces.isEmpty {
                        self.state.allPlaces = self.removeDuplicatePlaces(self.state.allPlaces + embeddedPlaces)
                    }

                    // Only fetch circles whose places weren't embedded in the response
                    let circlesMissingPlaces = connectionCircles.filter { circle in
                        circle.placesWithDetails == nil && (circle.placesCount ?? circle.places?.count ?? 0) > 0
                    }
                    if circlesMissingPlaces.isEmpty {
                        self.delegate?.updateAvailableCategories()
                        self.delegate?.finishConnectionFetch(connectionId)
                        // Keep the camera put — switching connections never
                        // re-frames the map (the coverage banner handles the
                        // case where the connection has nothing in view).
                        self.delegate?.refreshMapDisplay(adjustRegion: false)
                    } else {
                        self.fetchPlacesForConnectionCircles(circlesMissingPlaces, for: connectionId)
                    }
                case .failure(let error):
                    Logger.debug("❌ Failed to fetch circles for connection \(connectionId): \(error.localizedDescription)")
                    self.delegate?.finishConnectionFetch(connectionId)
                    self.delegate?.refreshMapDisplay(adjustRegion: false)
                }
            }
        }
    }

    /// Loads EVERY connection's full place set in the background. Viewport
    /// loading only fetches places near where the map is looking, so "All
    /// Connections / All Places" was silently missing anything far away (e.g.
    /// a connection's Hawaii trip) — and those regions never even appeared in
    /// the Place dropdown. Quiet merge: no zoom, no selection side effects.
    func prefetchAllConnectionPlaces() {
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let pending = NetworkManager.shared.connections
            .map { $0.otherUserId(currentUserId: currentUserId) }
            .filter { !$0.isEmpty && !state.prefetchedConnectionIds.contains($0) }
        guard !pending.isEmpty else { return }
        Logger.debug("📍 [Prefetch] Loading full place sets for \(pending.count) connections")

        var mergedPlaces: [Place] = []
        var mergedCircles: [Circle] = []
        var succeededIds: [String] = []
        let lock = NSLock()
        let group = DispatchGroup()

        for connectionId in pending {
            group.enter()
            APIService.shared.request(
                endpoint: "network/user-circles/\(connectionId)",
                method: .get,
                requiresAuth: true
            ) { (result: Result<UserCirclesResponse, APIError>) in
                if case .success(let response) = result {
                    let circles = response.data.circles
                    let places = circles.flatMap { $0.placesWithDetails ?? [] }
                    lock.lock()
                    mergedCircles.append(contentsOf: circles)
                    mergedPlaces.append(contentsOf: places)
                    // Only mark done when the payload embedded the places —
                    // otherwise leave it for the per-connection path to finish
                    let missing = circles.contains { $0.placesWithDetails == nil && ($0.placesCount ?? $0.places?.count ?? 0) > 0 }
                    if !missing { succeededIds.append(connectionId) }
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.state.prefetchedConnectionIds.formUnion(succeededIds)
            let knownIds = Set(self.state.networkCircles.map { $0.id })
            self.state.networkCircles.append(contentsOf: mergedCircles.filter { !knownIds.contains($0.id) })
            guard !mergedPlaces.isEmpty else { return }
            let countBefore = self.state.allPlaces.count
            self.state.allPlaces = self.removeDuplicatePlaces(self.state.allPlaces + mergedPlaces)
            Logger.debug("📍 [Prefetch] Merged \(self.state.allPlaces.count - countBefore) new places (total \(self.state.allPlaces.count))")
            guard self.state.allPlaces.count > countBefore else { return }
            self.state.cachedPlaces = self.state.allPlaces
            self.delegate?.updateAvailableCategories()
            // No zoom — the user is browsing; new pins just appear
            self.delegate?.refreshMapDisplay(adjustRegion: false)
        }
    }

    func fetchPlacesForConnectionCircles(_ connectionCircles: [Circle], for connectionId: String) {
        guard !connectionCircles.isEmpty else {
            delegate?.finishConnectionFetch(connectionId)
            delegate?.refreshMapDisplay(adjustRegion: true)
            return
        }

        Logger.debug("📍 Fetching places for \(connectionCircles.count) connection circles")
        var fetchedPlaces: [Place] = []
        let lock = NSLock()
        let group = DispatchGroup()

        for circle in connectionCircles {
            group.enter()
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                if case .success(let places) = result {
                    lock.lock()
                    fetchedPlaces.append(contentsOf: places)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            Logger.debug("📍 Connection places fetched: \(fetchedPlaces.count)")
            self.state.allPlaces = self.removeDuplicatePlaces(self.state.allPlaces + fetchedPlaces)
            self.delegate?.updateAvailableCategories()
            self.delegate?.finishConnectionFetch(connectionId)
            // Zoom is wanted here — the map should frame this connection's places
            self.delegate?.refreshMapDisplay(adjustRegion: true)
        }
    }

    // MARK: - Helpers

    /// First occurrence of each place id wins. No per-place logging — this
    /// runs on the main thread on every place merge.
    private func removeDuplicatePlaces(_ places: [Place]) -> [Place] {
        let deduplicated = HomeState.dedupe(places)
        if deduplicated.count < places.count {
            Logger.debug("⚠️ Removed \(places.count - deduplicated.count) duplicate places (\(places.count) → \(deduplicated.count))")
        }
        return deduplicated
    }
}
