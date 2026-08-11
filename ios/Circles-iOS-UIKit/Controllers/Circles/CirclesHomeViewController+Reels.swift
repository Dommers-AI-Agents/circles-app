import UIKit
import AVFoundation
import SafariServices

// Reels / Moments video subsystem for CirclesHomeViewController:
// the vertical-video collection view, its data source/delegates, and
// player lifecycle. Extracted from the main controller (Wave 4).

// MARK: - UICollectionViewDataSource

extension CirclesHomeViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == reelsCollectionView {
            return reels.count
        }
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == reelsCollectionView {
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
        return UICollectionViewCell()
    }
}

// MARK: - UICollectionViewDelegate

extension CirclesHomeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == reelsCollectionView {
            // Videos are played inline, no need to open full screen
            // Just ensure the video at this index is playing
            if indexPath.item != currentReelIndex {
                let offsetY = CGFloat(indexPath.item) * collectionView.frame.size.height
                collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: true)
            }
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension CirclesHomeViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView == reelsCollectionView {
            // Simply return the collection view's size - no need for complex calculations
            return collectionView.frame.size
        }
        return CGSize.zero
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView == reelsCollectionView {
            return 0
        }
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView == reelsCollectionView {
            return 0
        }
        return 0
    }
}

// MARK: - VideoLinkInputDelegate

// Keep the old delegate for backward compatibility if needed
extension CirclesHomeViewController: VideoLinkInputDelegate {
    func videoLinkInputDidFinish(with video: PlaceVideo) {
        // Convert to moment and handle
        let moment = PlaceMoment(from: video)
        contentUploadDidFinish(with: moment)
    }
    
    func videoLinkInputDidCancel() {
        // User cancelled - nothing to do
    }
}

// MARK: - Video Management

extension CirclesHomeViewController {
    func loadReelVideo(at index: Int) {
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
            Logger.debug("✅ CirclesHome: Skipping AVPlayer for embedded video \(reel.id)")
            Logger.debug("   - videoType: \(reel.videoType ?? "nil")")
            Logger.debug("   - embedPlatform: \(reel.embedPlatform ?? "nil")")
            Logger.debug("   - embedUrl: \(reel.embedUrl ?? "nil")")
            reelVideoStates[index] = .ready // Mark as ready so cell will be configured
            return
        }
        
        // For regular and direct videos, load AVPlayer
        guard let urlString = reel.videoUrl ?? reel.previewUrl,
              let url = URL(string: urlString) else { 
            Logger.debug("❌ CirclesHome: Invalid video URL for reel \(reel.id)")
            Logger.debug("   - videoUrl: \(reel.videoUrl ?? "nil")")
            Logger.debug("   - previewUrl: \(reel.previewUrl ?? "nil")")
            Logger.debug("   - title: \(reel.title)")
            Logger.debug("   - uploadStatus: \(reel.uploadStatus.rawValue)")
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
        Logger.debug("✅ CirclesHome: Loaded video for index \(index), URL: \(url)")
        
        // Force collection view to reload this cell to update with the player
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let indexPath = IndexPath(item: index, section: 0)
            
            // Only update if the cell is still showing the same reel
            if index < self.reels.count,
               let cell = self.reelsCollectionView.cellForItem(at: indexPath) as? VideoReelCell {
                cell.configure(with: reel, player: player)
                Logger.debug("📹 CirclesHome: Reconfigured cell with player for index \(index)")
            }
        }
    }
    
    func updateCurrentReelIndex() {
        let center = CGPoint(x: reelsCollectionView.frame.size.width / 2 + reelsCollectionView.contentOffset.x,
                            y: reelsCollectionView.frame.size.height / 2 + reelsCollectionView.contentOffset.y)
        
        if let indexPath = reelsCollectionView.indexPathForItem(at: center), indexPath.item != currentReelIndex {
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
    
    func playVideo(at index: Int) {
        guard index >= 0 && index < reels.count else { return }

        // Never start a moment unless the Moments segment is actually on screen.
        // Feed loads happen in the background on other tabs; playing from there
        // would start audio (and count a view) behind the user's back.
        guard contentSegmentedControl.selectedSegmentIndex == 1 else {
            Logger.debug("⏭ CirclesHome: Skipping playback at \(index) — Moments tab not selected")
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
                Logger.debug("▶️ CirclesHome: Playing video at index \(index) from beginning")
            }
        } else {
            // Load and play
            loadReelVideo(at: index)
            // Player will auto-play when ready if we add KVO like in VideoReelsViewController
        }
    }
    
    func pauseVideo(at index: Int) {
        if let player = reelPlayers[index] {
            player.pause()
            Logger.debug("⏸ CirclesHome: Paused video at index \(index)")
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

    /// Switch the home content to the Moments tab and land on a specific moment.
    /// Used when a moment activity (or its thumbnail) is tapped: instead of a
    /// modal player, drop the user into the inline Moments feed positioned on
    /// that moment (prepending it if the network feed doesn't already include
    /// it — e.g. paginated out, just created, or follower-gated).
    func openMomentInMomentsTab(_ video: PlaceVideo) {
        // Show the Moments segment. Setting selectedSegmentIndex in code does
        // not fire .valueChanged, so mirror contentSegmentChanged's case 1.
        contentSegmentedControl.selectedSegmentIndex = 1
        activityTableView.isHidden = true
        specialsTableView.isHidden = true
        reelsCollectionView.isHidden = false
        momentsCameraButton.isHidden = false
        activityHeaderLabel.text = "Moments"
        pauseAllVideos()

        // Load the network feed, then open on the tapped moment. The feed's
        // index 0 is the video updateReelsFeed plays, so move the target to the
        // front (insert if the feed doesn't include it) for a deterministic
        // landing with no scroll race. Reordering invalidates the index-keyed
        // player cache, so clear it before playing.
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

            self.reelsCollectionView.reloadData()
            self.reelsCollectionView.setContentOffset(.zero, animated: false)
            self.currentReelIndex = 0
            self.playVideo(at: 0)
        }
    }
    
    func trackReelView(at index: Int) {
        guard index >= 0 && index < reels.count else { return }
        
        let reel = reels[index]
        let endpoint = "videos/reels/\(reel.id)/view"
        
        // Send view tracking request
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: [:],
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            // Silent tracking, no need to handle response
            if case .failure(let error) = result {
                Logger.debug("❌ CirclesHome: Failed to track view for reel \(reel.id): \(error)")
            } else {
                Logger.debug("✅ CirclesHome: Successfully tracked view for reel \(reel.id)")
            }
        }
    }
    
    func preloadAdjacentVideos() {
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
    
    func releaseDistantVideos() {
        // Release videos that are more than 2 positions away
        for (index, player) in reelPlayers {
            if abs(index - currentReelIndex) > 2 {
                player.pause()
                reelPlayers.removeValue(forKey: index)
                reelVideoStates[index] = .notLoaded // Reset state for released videos
                Logger.debug("🗑 CirclesHome: Released video at index \(index)")
            }
        }
    }
}

// MARK: - VideoReelCellDelegate

extension CirclesHomeViewController: VideoReelCellDelegate {
    func videoReelCellDidTapLike(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        var reel = reels[indexPath.item]
        
        // Toggle like state optimistically
        let wasLiked = reel.likedByCurrentUser ?? false
        reel.likedByCurrentUser = !wasLiked
        reel.likeCount = wasLiked ? max(0, reel.likeCount - 1) : reel.likeCount + 1
        reels[indexPath.item] = reel
        
        // Update cell
        cell.configure(with: reel, player: reelPlayers[indexPath.item])
        
        // Call API
        let endpoint = wasLiked 
            ? "videos/reels/\(reel.id)/like"
            : "videos/reels/\(reel.id)/like"
        let method: RequestMethod = wasLiked ? .delete : .post
        
        APIService.shared.request(
            endpoint: endpoint,
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

                    if let cell = self.reelsCollectionView.cellForItem(at: indexPath) as? VideoReelCell {
                        cell.configure(with: reel, player: self.reelPlayers[indexPath.item])
                    }

                    Logger.debug("Failed to update like: \(error)")
                }
            }
        }
    }
    
    func videoReelCellDidTapFollow(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
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
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
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
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Generating share link...", from: self)
        
        // Call API to generate share link
        APIService.shared.request(
            endpoint: "videos/\(reel.id)/share",
            method: .post
        ) { [weak self] (result: Result<VideoShareLinkResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: false) {
                    switch result {
                    case .success(let response):
                        // Create share items with the generated URL
                        var shareItems: [Any] = []
                        
                        // Add share text
                        shareItems.append(response.data.shareText)
                        
                        // Add share URL
                        if let url = URL(string: response.data.shareUrl) {
                            shareItems.append(url)
                        }
                        
                        // Add thumbnail image if available
                        if let thumbnailUrl = response.data.thumbnailUrl,
                           let cachedImage = ImageService.shared.getCachedImage(for: thumbnailUrl) {
                            shareItems.append(cachedImage)
                        }
                        
                        let activityVC = UIActivityViewController(
                            activityItems: shareItems,
                            applicationActivities: nil
                        )
                        
                        // Customize the share sheet
                        activityVC.setValue(response.data.videoTitle ?? "Check out this moment", forKey: "subject")
                        
                        // For iPad
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = cell
                            popover.sourceRect = cell.bounds
                        }
                        
                        self?.present(activityVC, animated: true)
                        
                    case .failure(let error):
                        // Fallback to basic sharing if API fails
                        let shareText = "Check out this moment at \(reel.placeName) on Circles!"
                        let shareItems: [Any] = [shareText]
                        
                        let activityVC = UIActivityViewController(
                            activityItems: shareItems,
                            applicationActivities: nil
                        )
                        
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
        guard let indexPath = reelsCollectionView.indexPath(for: cell),
              let user = reels[indexPath.item].user else { return }
        
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    func videoReelCellDidTapPlace(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Pause all playing videos before navigating away
        pauseAllVideos()
        
        // Navigate to place detail
        showLoadingState()
        
        APIService.shared.request(
            endpoint: "places/\(reel.placeId)",
            method: .get
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            DispatchQueue.main.async {
                self?.hideLoadingState()
                
                switch result {
                case .success(let response):
                    if response.success {
                        let placeDetailVC = PlaceDetailViewController(place: response.place, circle: nil)
                        self?.navigationController?.pushViewController(placeDetailVC, animated: true)
                    }
                case .failure(let error):
                    self?.showError("Unable to load place details")
                    Logger.debug("❌ CirclesHome: Failed to fetch place details: \(error)")
                }
            }
        }
    }
    
    func videoReelCellDidTapReaction(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Pause all playing videos before presenting engagement view
        pauseAllVideos()
        
        // Present the engagement view controller
        let engagementVC = VideoEngagementViewController(video: reel)
        engagementVC.setSelectedSegment(0) // Show likes tab
        let navController = UINavigationController(rootViewController: engagementVC)
        present(navController, animated: true)
    }
    
    func videoReelCellDidTapActivityEngagement(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Pause all playing videos before presenting engagement view
        pauseAllVideos()
        
        // Present the engagement view controller
        let engagementVC = VideoEngagementViewController(video: reel)
        engagementVC.setSelectedSegment(1) // Show comments tab
        let navController = UINavigationController(rootViewController: engagementVC)
        present(navController, animated: true)
    }
    
    func videoReelCellDidTapLikeCount(_ cell: VideoReelCell) {
        // Not implementing like count view in the home feed
        // In a full implementation, we could show a modal with users who liked
    }

    func videoReelCellDidTapMoreOptions(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        pauseAllVideos()

        // Someone else's moment: report / unfollow / block instead of the
        // owner's delete-and-privacy menu
        if reel.userId != AuthService.shared.currentUser?.id {
            presentContentModerationSheet(
                contentType: "moment",
                contentId: reel.id,
                ownerId: reel.userId,
                ownerName: reel.user?.displayName,
                sourceView: cell,
                onContentHidden: { [weak self] in
                    guard let self = self, let idx = self.reels.firstIndex(where: { $0.id == reel.id }) else { return }
                    self.reels.remove(at: idx)
                    self.reelsCollectionView.reloadData()
                }
            )
            return
        }

        presentMomentOwnerMenu(
            for: reel,
            sourceView: cell,
            onPrivacyChanged: { [weak self] newVisibility in
                guard let self = self, let idx = self.reels.firstIndex(where: { $0.id == reel.id }) else { return }
                self.reels[idx].visibility = newVisibility
            },
            onDeleted: { [weak self] in
                guard let self = self, let idx = self.reels.firstIndex(where: { $0.id == reel.id }) else { return }
                self.reels.remove(at: idx)
                self.reelsCollectionView.reloadData()
            }
        )
    }
    
    // MARK: - Notification Badge Timer Management
    
    func startNotificationBadgeRefresh() {
        // Invalidate existing timer
        notificationBadgeTimer?.invalidate()

        // Start a timer that refreshes notification badge every 30 seconds
        // This ensures the badge stays current even if SSE events are missed
        notificationBadgeTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateNotificationBadge()
        }
    }
    
    func stopNotificationBadgeRefresh() {
        notificationBadgeTimer?.invalidate()
        notificationBadgeTimer = nil
        Logger.debug("🔔 [Timer] Stopped periodic notification badge refresh")
    }
}

