import UIKit

/// The profile's Moments tab: the user's own moments as a thumbnail grid.
/// Tap opens the full-screen reels player at that moment; long-press
/// offers delete on the signed-in user's own moments.
final class ProfileMomentsTabViewController: ProfileGridTabViewController {
    private(set) var videos: [PlaceVideo] = []
    private var isLoadingVideos = false

    init() {
        super.init(emptyText: "No moments yet")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func registerCells(in collectionView: UICollectionView) {
        collectionView.register(VideoThumbnailCell.self, forCellWithReuseIdentifier: "VideoThumbnailCell")
    }

    override var itemCount: Int { videos.count }

    override func cell(for collectionView: UICollectionView, at indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VideoThumbnailCell", for: indexPath) as! VideoThumbnailCell
        cell.configure(with: videos[indexPath.item])
        return cell
    }

    override func didSelectItem(at index: Int) {
        // Open full-screen reels viewer on the tapped moment
        let reelsVC = VideoReelsViewController(reels: videos, startIndex: index)
        reelsVC.modalPresentationStyle = .fullScreen
        present(reelsVC, animated: true)
    }

    override func contextMenu(at index: Int) -> UIMenu? {
        let video = videos[index]
        // Only the owner can delete
        guard video.userId == AuthService.shared.getUserId() else { return nil }
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.confirmDelete(video)
        }
        return UIMenu(title: "", children: [delete])
    }

    override func activate() {
        if videos.isEmpty && !isLoadingVideos {
            showLoading()
            fetchVideos()
        } else if !videos.isEmpty {
            showLoaded()
        }
    }

    // MARK: - Loading

    /// Fetches the user's moments. Safe to call while the tab is hidden (the
    /// profile load does): the grid only re-renders when this is the visible tab.
    func fetchVideos() {
        guard let userId = resolvedUserId else {
            Logger.debug("⚠️ ProfileMoments: No user ID available for fetching videos")
            isLoadingVideos = false
            loadingIndicator.stopAnimating()
            return
        }

        // Prevent multiple simultaneous fetches
        guard !isLoadingVideos else { return }
        isLoadingVideos = true

        let isCurrentUser = userId == AuthService.shared.getUserId()
        Logger.debug("📹 ProfileMoments: Fetching videos for user \(userId) (current user: \(isCurrentUser))")

        APIService.shared.getUserVideos(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingVideos = false

                switch result {
                case .success(let response):
                    // Filter out failed uploads and videos without URLs
                    self.videos = response.data.filter { video in
                        let hasValidUrl = video.contentType == "photo" ? video.thumbnailUrl != nil : video.videoUrl != nil
                        return video.uploadStatus == .ready && hasValidUrl
                    }
                    Logger.debug("📹 ProfileMoments: Fetched \(response.data.count) videos, showing \(self.videos.count) valid ones")

                    // Cache the user's own videos for offline access
                    if isCurrentUser && !response.data.isEmpty {
                        VideoStorageService.shared.cacheUserVideos(response.data)
                    }

                    if self.isActiveTab {
                        self.showLoaded()
                    }

                case .failure(let error):
                    Logger.debug("❌ ProfileMoments: Failed to fetch videos: \(error.localizedDescription)")
                    // Don't show an error to the user, just leave the grid empty
                    self.videos = []
                    if self.isActiveTab {
                        self.showLoaded()
                    }
                }
            }
        }
    }

    // MARK: - Delete

    private func confirmDelete(_ video: PlaceVideo) {
        AlertPresenter.showConfirmation(
            title: "Delete Content",
            message: "Are you sure you want to delete this \(video.contentType == "photo" ? "photo" : "video")? This action cannot be undone.",
            confirmTitle: "Delete",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in self?.delete(video) }
        )
    }

    private func delete(_ video: PlaceVideo) {
        let loadingAlert = AlertPresenter.showLoading(message: "Deleting...", from: self)

        APIService.shared.deleteVideo(videoId: video.id) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        // Clear the moment's media from cache
                        for url in [video.videoUrl, video.thumbnailUrl, video.previewUrl].compactMap({ $0 }) {
                            MediaCacheService.shared.clearImage(for: url)
                        }

                        if let index = self.videos.firstIndex(where: { $0.id == video.id }) {
                            self.videos.remove(at: index)
                            self.collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
                        }
                        self.updateContentHeight()
                        self.emptyLabel.isHidden = !self.videos.isEmpty

                        self.showSuccess("Content deleted successfully")

                        // The home feed drops the moment's activity rows
                        NotificationCenter.default.post(
                            name: Notification.Name("MomentDeleted"),
                            object: nil,
                            userInfo: ["videoId": video.id, "userId": video.userId]
                        )
                        Logger.debug("📢 Posted MomentDeleted notification for video: \(video.id)")

                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
}
