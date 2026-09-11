import UIKit
import AVFoundation

/// The home screen's Moments tab: the vertical, paging video feed
/// (`videos/reels/feed`), its AVPlayer cache and autoplay, and the per-cell
/// actions (like, follow, comment, share, profile, place, moderation).
///
/// Playback rules: a moment only ever starts while this is the visible tab
/// (`isActiveTab`), and the audio session is claimed at play time — not when
/// a player is created — so background music survives feed loads on other
/// tabs. The host pauses everything when the segment switches away or the
/// screen disappears.
final class HomeMomentsViewController: BaseViewController, HomeContentTab {
    weak var host: HomeContentTabHost?
    var isActiveTab = false

    var reels: [PlaceVideo] = []
    private var isLoadingReels = false
    private var reelsOffset = 0
    private var hasMoreReels = true
    private var isLoadingMoreReels = false

    /// Track current video index for auto-play
    private var currentReelIndex = 0
    private var reelPlayers: [Int: AVPlayer] = [:]

    /// Track video loading states to prevent index misalignment
    enum VideoLoadState {
        case notLoaded
        case loading
        case ready
        case failed
    }
    private var reelVideoStates: [Int: VideoLoadState] = [:]

    let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = .zero
        // Item size comes from the delegate (the collection view's own size)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never // Full-bleed video, like VideoReelsViewController
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    private let statusView = HomeTabStatusView()

    // The host's segment switch drives loading; nothing loads on its own.
    override var loadsDataOnViewDidLoad: Bool { false }
    override var reloadsDataOnAppear: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        view.addSubview(collectionView)
        view.addSubview(statusView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.topAnchor.constraint(equalTo: view.topAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(VideoReelCell.self, forCellWithReuseIdentifier: "VideoReelCell")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Cells are sized to the collection view, so re-measure on every layout pass
        if collectionView.bounds.width > 0 {
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: nil)
    }

    // MARK: - HomeContentTab

    func tabDidBecomeVisible() {
        // Reset to first video
        currentReelIndex = 0

        // Force layout update before showing collection view
        host?.layoutContentIfNeeded()

        // Invalidate layout to ensure proper sizing
        collectionView.collectionViewLayout.invalidateLayout()

        // Reset collection view to top to fix Y offset issue
        collectionView.setContentOffset(.zero, animated: false)

        // Scroll to first item explicitly
        if !reels.isEmpty {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
        }

        // Always refresh when switching to Moments to get the latest videos;
        // fetchReels plays the first one after loading.
        fetchReels()
    }

    func tabWillHide() {
        pauseAllVideos()
    }

    func refreshTab() {
        fetchReels()
    }

    /// Land on a specific moment: used when a moment activity (or its
    /// thumbnail) is tapped. The host has already switched the segment to
    /// Moments; this loads the network feed, moves the target to the front
    /// (prepending it if the feed doesn't include it — paginated out, just
    /// created, or follower-gated) and plays it. Reordering invalidates the
    /// index-keyed player cache, so it's cleared before playing.
    func present(moment video: PlaceVideo) {
        view.isHidden = false
        isActiveTab = true
        pauseAllVideos()

        fetchReels { [weak self] _ in
            guard let self = self else { return }
            if let existing = self.reels.firstIndex(where: { $0.id == video.id }) {
                if existing != 0 {
                    let moment = self.reels.remove(at: existing)
                    self.reels.insert(moment, at: 0)
                }
            } else {
                self.reels.insert(video, at: 0)
                self.reelsOffset = self.reels.count
            }

            for player in self.reelPlayers.values { player.pause() }
            self.reelPlayers.removeAll()
            self.reelVideoStates.removeAll()

            self.collectionView.reloadData()
            self.collectionView.setContentOffset(.zero, animated: false)
            self.currentReelIndex = 0
            self.playVideo(at: 0)
        }
    }

    /// The home came back on screen with this tab showing (e.g. back from a
    /// place page): resume the current moment where it was paused, without
    /// counting a new view.
    func resumePlaybackIfVisible() {
        guard isActiveTab, !view.isHidden, currentReelIndex < reels.count else { return }
        guard reels[currentReelIndex].contentType != "photo" else { return }
        if let player = reelPlayers[currentReelIndex] {
            AudioSessionManager.shared.beginPlayback()
            player.play()
        } else {
            playVideo(at: currentReelIndex)
        }
    }

    /// Drops every moment by `userId` (the user just blocked them).
    func removeReels(by userId: String) {
        reels.removeAll { $0.userId == userId }
        collectionView.reloadData()
    }

    // MARK: - Loading

    func fetchReels(loadMore: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !isLoadingReels && !isLoadingMoreReels else {
            completion?(false)
            return
        }

        if loadMore && !hasMoreReels {
            completion?(false)
            return
        }

        if loadMore {
            isLoadingMoreReels = true
        } else {
            isLoadingReels = true
            statusView.isLoading = true
            reelsOffset = 0
            hasMoreReels = true

            // Clear existing players and states when loading fresh data
            for player in reelPlayers.values {
                player.pause()
            }
            AudioSessionManager.shared.endPlayback()
            reelPlayers.removeAll()
            reelVideoStates.removeAll()
        }

        let offset = loadMore ? reelsOffset : 0
        let endpoint = "videos/reels/feed?limit=20&offset=\(offset)"

        APIService.shared.request(
            endpoint: endpoint,
            method: .get
        ) { [weak self] (result: Result<VideosResponse, APIError>) in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if loadMore {
                    self.isLoadingMoreReels = false
                } else {
                    self.isLoadingReels = false
                    self.statusView.isLoading = false
                }

                switch result {
                case .success(let response):
                    // Filter out failed uploads and videos without URLs
                    let validReels = response.data.filter { video in
                        let hasValidUrl = video.contentType == "photo" ? video.thumbnailUrl != nil : video.videoUrl != nil
                        return video.uploadStatus == .ready && hasValidUrl
                    }

                    if loadMore {
                        self.reels.append(contentsOf: validReels)
                    } else {
                        self.reels = validReels
                    }

                    self.reelsOffset = self.reels.count
                    self.hasMoreReels = response.hasMore
                    self.updateReelsFeed()

                case .failure(let error):
                    Logger.debug("❌ Error fetching reels: \(error)")

                    // Handle specific error types gracefully
                    var isHandledError = false

                    if case APIError.serverError = error {
                        // Firestore's "too many disjunctions" limit on big networks
                        let errorString = error.localizedDescription
                        if errorString.contains("Too many disjunctions") || errorString.contains("32 disjunctions") {
                            Logger.debug("🔍 Detected Firestore disjunction limit error - showing user-friendly message")
                            if !loadMore {
                                self.showFirestoreQueryLimitError()
                                isHandledError = true
                            }
                        }
                    } else if case APIError.rateLimited = error {
                        Logger.debug("🔍 Rate limited loading Moments feed - showing fallback content")
                        if !loadMore {
                            self.showMomentsFeedFallback()
                            isHandledError = true
                        }
                    }

                    // Only show empty state if error wasn't handled with a specific fallback
                    if !isHandledError && !loadMore {
                        self.reels = []
                        self.updateReelsFeed()
                    }
                }

                self.host?.endRefreshing()
                completion?(true)
            }
        }
    }

    private func updateReelsFeed() {
        isLoadingReels = false
        statusView.isLoading = false

        // Update empty state
        statusView.message = reels.isEmpty ? "No moments yet. Be the first to share a moment!" : nil

        // Reset to first video when loading new data
        currentReelIndex = 0

        // Force layout update
        host?.layoutContentIfNeeded()

        // Invalidate layout to ensure proper sizing
        collectionView.collectionViewLayout.invalidateLayout()

        // Reload collection
        collectionView.reloadData()

        // Preload video for first visible item after reload
        if !reels.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.reels[0].contentType != "photo" && self.reelVideoStates[0] == nil {
                    self.reelVideoStates[0] = .loading
                    self.loadReelVideo(at: 0)
                }
            }
        }

        // Reset scroll position to top after loading new data
        collectionView.setContentOffset(.zero, animated: false)

        // Ensure we're at the first item
        if !reels.isEmpty {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
        }

        host?.layoutContentIfNeeded()

        // Start playing the first video ONLY if Moments is the visible tab.
        // The feed is also fetched on launch while Activity is showing; playing
        // here unconditionally started audio the user never asked for and cut
        // off whatever they were listening to.
        if isActiveTab && !reels.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.playVideo(at: 0)
            }
        }
    }

    private func showFirestoreQueryLimitError() {
        isLoadingReels = false
        statusView.isLoading = false
        statusView.message = "Too much content to load right now! Try refreshing in a few moments, or check back later for your Moments feed."
        Logger.debug("🔍 Showing user-friendly message for Firestore query limit")

        // Clear reels array to show empty state
        reels = []
        collectionView.reloadData()

        // Auto-retry after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            Logger.debug("🔍 Auto-retrying Moments feed after Firestore error")
            self?.fetchReels()
        }
    }

    private func showMomentsFeedFallback() {
        isLoadingReels = false
        statusView.isLoading = false
        statusView.message = "Feed temporarily unavailable due to high activity. Pull to refresh to try again!"
        Logger.debug("🔍 Showing fallback message for rate limited Moments feed")

        // Clear reels array to show empty state; pull-to-refresh retries
        reels = []
        collectionView.reloadData()
    }

    // MARK: - Video management

    private func loadReelVideo(at index: Int) {
        guard index >= 0 && index < reels.count else {
            reelVideoStates[index] = .failed
            return
        }

        let reel = reels[index]

        // Skip loading video player for photos
        if reel.contentType == "photo" {
            reelVideoStates[index] = .ready // Photos don't need video loading
            return
        }

        // Skip loading AVPlayer for embedded videos - they use EmbeddedVideoPlayerView
        if reel.isEmbedded {
            Logger.debug("✅ Moments: Skipping AVPlayer for embedded video \(reel.id) (\(reel.embedPlatform ?? "nil"))")
            reelVideoStates[index] = .ready // Mark as ready so cell will be configured
            return
        }

        // For regular and direct videos, load AVPlayer
        guard let urlString = reel.videoUrl ?? reel.previewUrl,
              let url = URL(string: urlString) else {
            Logger.debug("❌ Moments: Invalid video URL for reel \(reel.id) (videoUrl: \(reel.videoUrl ?? "nil"), previewUrl: \(reel.previewUrl ?? "nil"), status: \(reel.uploadStatus.rawValue))")
            reelVideoStates[index] = .failed
            return
        }

        // Create player
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none // Loop video

        // NOTE: the audio session is deliberately NOT activated here. Creating a
        // player happens on launch/preload even when the user is on the Activity
        // tab; taking the session there would kill their background music before
        // anything plays. It's claimed in playVideo(at:) instead.

        reelPlayers[index] = player
        reelVideoStates[index] = .ready
        Logger.debug("✅ Moments: Loaded video for index \(index), URL: \(url)")

        // Force collection view to reload this cell to update with the player
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let indexPath = IndexPath(item: index, section: 0)

            // Only update if the cell is still showing the same reel
            if index < self.reels.count,
               let cell = self.collectionView.cellForItem(at: indexPath) as? VideoReelCell {
                cell.configure(with: reel, player: player)
            }
        }
    }

    private func updateCurrentReelIndex() {
        let center = CGPoint(x: collectionView.frame.size.width / 2 + collectionView.contentOffset.x,
                             y: collectionView.frame.size.height / 2 + collectionView.contentOffset.y)

        if let indexPath = collectionView.indexPathForItem(at: center), indexPath.item != currentReelIndex {
            // Pause previous video
            pauseVideo(at: currentReelIndex)

            // Update current index
            currentReelIndex = indexPath.item

            // Play new video
            playVideo(at: currentReelIndex)

            // Preload adjacent videos
            preloadAdjacentVideos()
        }
    }

    private func playVideo(at index: Int) {
        guard index >= 0 && index < reels.count else { return }

        // Never start a moment unless the Moments segment is actually on screen.
        // Feed loads happen in the background on other tabs; playing from there
        // would start audio (and count a view) behind the user's back.
        guard isActiveTab else {
            Logger.debug("⏭ Moments: Skipping playback at \(index) — Moments tab not selected")
            return
        }

        // Track view for both photos and videos
        trackReelView(at: index)

        // Check if it's a photo
        if reels[index].contentType == "photo" {
            return
        }

        // Play video if available
        if let player = reelPlayers[index] {
            // Take over the audio session only now that a moment is actually
            // playing, so background music survives until this point.
            AudioSessionManager.shared.beginPlayback()

            // Restart from beginning when returning to video
            player.seek(to: .zero) { _ in
                player.play()
                Logger.debug("▶️ Moments: Playing video at index \(index) from beginning")
            }
        } else {
            // Load and play
            loadReelVideo(at: index)
        }
    }

    private func pauseVideo(at index: Int) {
        if let player = reelPlayers[index] {
            player.pause()
            Logger.debug("⏸ Moments: Paused video at index \(index)")
        }
    }

    func pauseAllVideos() {
        for player in reelPlayers.values {
            player.pause()
        }

        // Nothing is playing any more — hand the audio session back so the
        // user's music/podcast picks up where it left off.
        AudioSessionManager.shared.endPlayback()
    }

    private func trackReelView(at index: Int) {
        guard index >= 0 && index < reels.count else { return }

        let reel = reels[index]
        // Silent tracking, no need to handle the response
        APIService.shared.request(
            endpoint: "videos/reels/\(reel.id)/view",
            method: .post,
            body: [:],
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            if case .failure(let error) = result {
                Logger.debug("❌ Moments: Failed to track view for reel \(reel.id): \(error)")
            }
        }
    }

    private func preloadAdjacentVideos() {
        // Preload videos around current index
        let preloadRange = max(0, currentReelIndex - 1)...min(reels.count - 1, currentReelIndex + 1)

        for index in preloadRange {
            let videoState = reelVideoStates[index] ?? .notLoaded
            if videoState == .notLoaded && reels[index].contentType != "photo" {
                reelVideoStates[index] = .loading
                loadReelVideo(at: index)
            }
        }

        // Clean up distant videos to save memory
        releaseDistantVideos()
    }

    private func releaseDistantVideos() {
        // Release videos that are more than 2 positions away
        for (index, player) in reelPlayers {
            if abs(index - currentReelIndex) > 2 {
                player.pause()
                reelPlayers.removeValue(forKey: index)
                reelVideoStates[index] = .notLoaded // Reset state for released videos
                Logger.debug("🗑 Moments: Released video at index \(index)")
            }
        }
    }
}

// MARK: - Collection view

extension HomeMomentsViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        reels.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VideoReelCell", for: indexPath) as! VideoReelCell
        let reel = reels[indexPath.item]

        // Check video state for this index
        let videoState = reelVideoStates[indexPath.item] ?? .notLoaded

        // Load video if needed and not already loading
        if reel.contentType != "photo" && !reel.isEmbedded && videoState == .notLoaded {
            reelVideoStates[indexPath.item] = .loading
            loadReelVideo(at: indexPath.item)
        } else if reel.isEmbedded && videoState == .notLoaded {
            // Mark embedded videos as ready immediately
            reelVideoStates[indexPath.item] = .ready
        }

        // Only pass player for non-embedded videos
        let player: AVPlayer? = {
            if reel.contentType == "photo" || reel.isEmbedded {
                return nil // Photos and embedded videos don't use AVPlayer
            }
            return videoState == .ready ? reelPlayers[indexPath.item] : nil
        }()

        // Configure cell - it will handle embedded videos internally
        cell.configure(with: reel, player: player)
        cell.delegate = self
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // Videos are played inline, no need to open full screen —
        // just ensure the video at this index is playing
        if indexPath.item != currentReelIndex {
            let offsetY = CGFloat(indexPath.item) * collectionView.frame.size.height
            collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // One full-size page per moment
        collectionView.frame.size
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        0
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        0
    }

    // MARK: Scrolling — pagination and the current-page player

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let contentHeight = scrollView.contentSize.height
        let scrollOffset = scrollView.contentOffset.y
        let frameHeight = scrollView.frame.size.height

        if scrollOffset > contentHeight - frameHeight * 1.5 {
            if !isLoadingMoreReels && hasMoreReels {
                fetchReels(loadMore: true)
            }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentReelIndex()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateCurrentReelIndex()
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateCurrentReelIndex()
    }
}

// MARK: - VideoReelCellDelegate

extension HomeMomentsViewController: VideoReelCellDelegate {
    func videoReelCellDidTapLike(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        var reel = reels[indexPath.item]

        // Toggle like state optimistically
        let wasLiked = reel.likedByCurrentUser ?? false
        reel.likedByCurrentUser = !wasLiked
        reel.likeCount = wasLiked ? max(0, reel.likeCount - 1) : reel.likeCount + 1
        reels[indexPath.item] = reel

        // Update cell
        cell.configure(with: reel, player: reelPlayers[indexPath.item])

        // Call API
        let method: RequestMethod = wasLiked ? .delete : .post
        APIService.shared.request(
            endpoint: "videos/reels/\(reel.id)/like",
            method: method,
            requiresAuth: true
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            if case .success(let response) = result, !wasLiked {
                // Liking someone's moment earns a nickel — celebrate it here
                // too, not just in the full-screen player
                PiggyBankDepositView.play(credit: response.piggyBank)
            }
            if case .failure(let error) = result {
                // Revert on failure
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    reel.likedByCurrentUser = wasLiked
                    reel.likeCount = wasLiked ? reel.likeCount + 1 : max(0, reel.likeCount - 1)
                    self.reels[indexPath.item] = reel

                    if let cell = self.collectionView.cellForItem(at: indexPath) as? VideoReelCell {
                        cell.configure(with: reel, player: self.reelPlayers[indexPath.item])
                    }

                    Logger.debug("Failed to update like: \(error)")
                }
            }
        }
    }

    func videoReelCellDidTapFollow(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let ownerId = reels[indexPath.item].userId

        APIService.shared.request(
            endpoint: "users/\(ownerId)/follow",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    AuthService.shared.recordFollowChange(userId: ownerId, isFollowing: true)
                    PiggyBankDepositView.play(credit: response.piggyBank)
                    self.markReelOwnerFollowed(ownerId)
                    cell.showFollowConfirmed()
                case .failure(let error):
                    // "Already following" means the local state was stale —
                    // adopt the server's answer and hide the button
                    if error.serverMessage?.lowercased().contains("already following") == true {
                        self.markReelOwnerFollowed(ownerId)
                        cell.showFollowConfirmed()
                    } else {
                        cell.resetFollowButton()
                        Logger.debug("Failed to follow from reel: \(error)")
                    }
                }
            }
        }
    }

    /// Stamp isFollowing on every loaded reel from this owner so recycled
    /// cells render the followed state.
    private func markReelOwnerFollowed(_ ownerId: String) {
        for index in reels.indices where reels[index].userId == ownerId {
            if let user = reels[index].user {
                reels[index].user = user.copy(isFollowing: true)
            }
        }
    }

    func videoReelCellDidTapComment(_ cell: VideoReelCell) {
        // Not opening full screen - just show comments in a sheet
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]

        let commentsVC = VideoCommentsViewController(video: reel)
        let nav = UINavigationController(rootViewController: commentsVC)
        nav.modalPresentationStyle = .pageSheet

        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        present(nav, animated: true)
    }

    func videoReelCellDidTapShare(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]

        let loadingAlert = AlertPresenter.showLoading(message: "Generating share link...", from: self)

        APIService.shared.request(
            endpoint: "videos/\(reel.id)/share",
            method: .post
        ) { [weak self] (result: Result<VideoShareLinkResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: false) {
                    switch result {
                    case .success(let response):
                        var shareItems: [Any] = [response.data.shareText]
                        if let url = URL(string: response.data.shareUrl) {
                            shareItems.append(url)
                        }
                        // Add thumbnail image if available
                        if let thumbnailUrl = response.data.thumbnailUrl,
                           let cachedImage = ImageService.shared.getCachedImage(for: thumbnailUrl) {
                            shareItems.append(cachedImage)
                        }

                        let activityVC = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
                        activityVC.setValue(response.data.videoTitle ?? "Check out this moment", forKey: "subject")
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = cell
                            popover.sourceRect = cell.bounds
                        }
                        self?.present(activityVC, animated: true)

                    case .failure(let error):
                        // Fallback to basic sharing if API fails
                        let shareText = "Check out this moment at \(reel.placeName) on Circles!"
                        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = cell
                            popover.sourceRect = cell.bounds
                        }
                        self?.present(activityVC, animated: true)

                        Logger.debug("Failed to generate share link: \(error)")
                    }
                }
            }
        }
    }

    func videoReelCellDidTapProfile(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let user = reels[indexPath.item].user else { return }

        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }

    func videoReelCellDidTapPlace(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]

        // Pause all playing videos before navigating away
        pauseAllVideos()

        let loading = AlertPresenter.showLoading(message: "Loading place...", from: self)
        APIService.shared.request(
            endpoint: "places/\(reel.placeId)",
            method: .get
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let response):
                        if response.success {
                            let placeDetailVC = PlaceDetailViewController(place: response.place, circle: nil)
                            self.navigationController?.pushViewController(placeDetailVC, animated: true)
                        }
                    case .failure(let error):
                        self.showError("Unable to load place details")
                        Logger.debug("❌ Moments: Failed to fetch place details: \(error)")
                    }
                }
            }
        }
    }

    func videoReelCellDidTapReaction(_ cell: VideoReelCell) {
        presentEngagement(for: cell, segment: 0) // Likes tab
    }

    func videoReelCellDidTapActivityEngagement(_ cell: VideoReelCell) {
        presentEngagement(for: cell, segment: 1) // Comments tab
    }

    private func presentEngagement(for cell: VideoReelCell, segment: Int) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]

        // Pause all playing videos before presenting engagement view
        pauseAllVideos()

        let engagementVC = VideoEngagementViewController(video: reel)
        engagementVC.setSelectedSegment(segment)
        let navController = UINavigationController(rootViewController: engagementVC)
        present(navController, animated: true)
    }

    func videoReelCellDidTapLikeCount(_ cell: VideoReelCell) {
        // Not implementing like count view in the home feed
    }

    func videoReelCellDidTapMoreOptions(_ cell: VideoReelCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        pauseAllVideos()

        let removeReel: () -> Void = { [weak self] in
            guard let self = self, let idx = self.reels.firstIndex(where: { $0.id == reel.id }) else { return }
            self.reels.remove(at: idx)
            self.collectionView.reloadData()
        }

        // Someone else's moment: report / unfollow / block instead of the
        // owner's delete-and-privacy menu
        if reel.userId != AuthService.shared.currentUser?.id {
            let moderate: () -> Void = { [weak self] in
                self?.presentContentModerationSheet(
                    contentType: "moment",
                    contentId: reel.id,
                    ownerId: reel.userId,
                    ownerName: reel.user?.displayName,
                    sourceView: cell,
                    onContentHidden: removeReel
                )
            }
            // Tagged in someone else's moment → self-service untag first
            if reel.isTagged(AuthService.shared.currentUser?.id) {
                presentMomentTaggedViewerMenu(
                    for: reel,
                    sourceView: cell,
                    onUntagged: { [weak self] in
                        guard let self = self, let idx = self.reels.firstIndex(where: { $0.id == reel.id }) else { return }
                        self.reels[idx].taggedUsers?.removeAll { $0.id == AuthService.shared.currentUser?.id }
                        self.collectionView.reloadData()
                    },
                    onMoreOptions: moderate
                )
                return
            }
            moderate()
            return
        }

        presentMomentOwnerMenu(
            for: reel,
            sourceView: cell,
            onPrivacyChanged: { [weak self] newVisibility in
                guard let self = self, let idx = self.reels.firstIndex(where: { $0.id == reel.id }) else { return }
                self.reels[idx].visibility = newVisibility
            },
            onDeleted: removeReel
        )
    }
}
