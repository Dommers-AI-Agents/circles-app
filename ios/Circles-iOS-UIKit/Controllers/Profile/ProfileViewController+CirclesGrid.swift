import UIKit
import MapKit
import CoreLocation
import PhotosUI

// Circles collection view: data source, delegates, drag/drop, create/edit for ProfileViewController. Extracted from the main controller (Wave 4).

// MARK: - UICollectionViewDataSource
extension ProfileViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == videosCollectionView {
            return videos.count
        } else if collectionView == uploadsCollectionView {
            return uploadGroups.count // one tile per place
        }
        return circles.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == videosCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VideoThumbnailCell", for: indexPath) as! VideoThumbnailCell
            let video = videos[indexPath.item]
            cell.configure(with: video)
            return cell
        } else if collectionView == uploadsCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "UploadThumbnailCell", for: indexPath) as! UploadThumbnailCell
            cell.configure(with: uploadGroups[indexPath.item])
            return cell
        }
        
        let circle = circles[indexPath.item]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CircleCell", for: indexPath) as! CircleCell
        cell.configure(with: circle)
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension ProfileViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == videosCollectionView {
            // Open full-screen reels viewer
            let reelsVC = VideoReelsViewController(reels: videos, startIndex: indexPath.item)
            reelsVC.modalPresentationStyle = .fullScreen
            present(reelsVC, animated: true)
        } else if collectionView == uploadsCollectionView {
            // Open the place's page — its media carousel scrolls through all of
            // the place's photos (the uploads included). Long-press the tile to
            // manage/delete individual uploads.
            navigateToPlaceDetail(from: uploadGroups[indexPath.item].cover)
        } else {
            let circle = circles[indexPath.item]
            let detailVC = CircleDetailViewController(circle: circle)
            navigationController?.pushViewController(detailVC, animated: true)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        // Handle context menu for videos
        if collectionView == videosCollectionView {
            let video = videos[indexPath.item]
            
            // Only show delete for user's own videos
            guard video.userId == AuthService.shared.getUserId() else { return nil }
            
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self = self else { return UIMenu(title: "", children: []) }
                
                let deleteAction = UIAction(
                    title: "Delete",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self.confirmDeleteVideo(video, at: indexPath)
                }
                
                return UIMenu(title: "", children: [deleteAction])
            }
        } else if collectionView == uploadsCollectionView {
            // Tap opens the place page; long-press manages this place's photos
            // in a gallery where individual uploads can be deleted.
            guard indexPath.item < uploadGroups.count else { return nil }
            let group = uploadGroups[indexPath.item]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let manage = UIAction(title: "View / manage photos", image: UIImage(systemName: "photo.on.rectangle")) { _ in
                    self?.openUploadsGallery(for: group)
                }
                return UIMenu(children: [manage])
            }
        }
        
        // Handle context menu for circles
        let circle = circles[indexPath.item]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return UIMenu(title: "", children: []) }
            
            let editAction = UIAction(
                title: "Edit Circle",
                image: UIImage(systemName: "pencil")
            ) { _ in
                self.editCircle(circle)
            }
            
            let shareAction = UIAction(
                title: "Share Circle",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                self.shareCircle(circle, from: indexPath)
            }
            
            let deleteAction = UIAction(
                title: "Delete Circle",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self.deleteCircle(circle, at: indexPath)
            }
            
            return UIMenu(title: circle.name, children: [editAction, shareAction, deleteAction])
        }
    }
    
    func editCircle(_ circle: Circle) {
        let editVC = EditCircleViewController(circle: circle)
        editVC.delegate = self
        navigationController?.pushViewController(editVC, animated: true)
    }
    
    func shareCircle(_ circle: Circle, from indexPath: IndexPath) {
        var shareText = "🔵 \(circle.name)\n"
        
        if let description = circle.description, !description.isEmpty {
            shareText += "\(description)\n"
        }
        
        // Calculate member count from sharedWith and followers
        let memberCount = 1 + (circle.sharedWith?.count ?? 0) + (circle.followers?.count ?? 0)
        shareText += "\n👥 \(memberCount) members"
        shareText += "\n📍 \(circle.places?.count ?? 0) places"
        
        // Add privacy info
        switch circle.privacy {
        case .public:
            shareText += "\n🌐 Public Circle"
        case .myNetwork:
            shareText += "\n👥 My Network"
        case .private:
            shareText += "\n🔒 Private Circle"
        }
        
        shareText += "\n\nJoin me on Circles:"

        // Universal link: opens the circle in-app when installed, public
        // circle preview page + App Store fallback otherwise
        let activityItems: [Any] = [shareText, ShareLinks.circle(id: circle.id)]
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // For iPad - set the source view for the popover
        if let popover = activityViewController.popoverPresentationController,
           let cell = circlesCollectionView.cellForItem(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        
        present(activityViewController, animated: true)
    }
    
    func deleteCircle(_ circle: Circle, at indexPath: IndexPath) {
        AlertPresenter.showConfirmation(
            title: "Delete Circle",
            message: "Are you sure you want to delete '\(circle.name)'? This action cannot be undone.",
            confirmTitle: "Delete",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in
                guard let self = self else { return }
                
                CircleService.shared.deleteCircle(id: circle.id) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.didDeleteCircle(circle.id)
                        case .failure(let error):
                            self.showError("Failed to delete circle: \(error.localizedDescription)")
                        }
                    }
                }
            }
        )
    }
}

// MARK: - UICollectionViewDelegateFlowLayout
extension ProfileViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView == videosCollectionView {
            // Instagram-style 3-column grid with square items
            let spacing: CGFloat = 2
            let numberOfColumns: CGFloat = 3
            let totalSpacing = spacing * (numberOfColumns - 1)
            let itemWidth = (collectionView.bounds.width - totalSpacing) / numberOfColumns
            return CGSize(width: itemWidth, height: itemWidth) // Square items
        } else if collectionView == uploadsCollectionView {
            // Instagram-style 3-column grid with square items (same as videos)
            let spacing: CGFloat = 2
            let numberOfColumns: CGFloat = 3
            let totalSpacing = spacing * (numberOfColumns - 1)
            let itemWidth = (collectionView.bounds.width - totalSpacing) / numberOfColumns
            return CGSize(width: itemWidth, height: itemWidth) // Square items
        } else {
            // Circular grid with 3 columns
            let spacing: CGFloat = 12
            let numberOfColumns: CGFloat = 3
            let totalSpacing = spacing * (numberOfColumns - 1)
            let itemWidth = (collectionView.bounds.width - totalSpacing) / numberOfColumns
            let itemHeight = itemWidth + 50 // Extra height for labels below circles
            return CGSize(width: itemWidth, height: itemHeight)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return (collectionView == videosCollectionView || collectionView == uploadsCollectionView) ? 2 : 16
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return (collectionView == videosCollectionView || collectionView == uploadsCollectionView) ? 2 : 12
    }
}

// MARK: - CreateCircleDelegate
extension ProfileViewController: CreateCircleDelegate {
    func didCreateCircle(_ circle: Circle) {
        circles.insert(circle, at: 0)
        circlesCollectionView.reloadData()
        updateCollectionViewHeight()
        
        // Update stats
        circlesStatView.configure(number: "\(circles.count)", title: "Circles")
    }
}

// MARK: - EditCircleDelegate
extension ProfileViewController: EditCircleDelegate {
    func didUpdateCircle(_ circle: Circle) {
        if let index = circles.firstIndex(where: { $0.id == circle.id }) {
            circles[index] = circle
            circlesCollectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        }
    }
    
    func didDeleteCircle(_ circleId: String) {
        if let index = circles.firstIndex(where: { $0.id == circleId }) {
            circles.remove(at: index)
            circlesCollectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
            updateCollectionViewHeight()
            
            // Update stats
            circlesStatView.configure(number: "\(circles.count)", title: "Circles")
        }
    }
}


// MARK: - UICollectionViewDragDelegate
extension ProfileViewController: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard collectionView == circlesCollectionView else { return [] }
        
        // Only allow dragging for current user's own circles
        guard user?.id == AuthService.shared.getUserId() else { return [] }
        
        let circle = circles[indexPath.item]
        let itemProvider = NSItemProvider(object: circle.id as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = circle
        return [dragItem]
    }
}

// MARK: - UICollectionViewDropDelegate
extension ProfileViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        guard collectionView == circlesCollectionView else { return false }
        return session.canLoadObjects(ofClass: NSString.self)
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard collectionView == circlesCollectionView else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        
        // Only allow drops for current user's own profile
        guard user?.id == AuthService.shared.getUserId() else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        
        // Check what's being dragged (should be a circle)
        guard let dragItem = session.items.first,
              let _ = dragItem.localObject as? Circle else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        
        // Allow reordering
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
        // Clean up any visual feedback
        collectionView.visibleCells.forEach { cell in
            if let circleCell = cell as? CircleCell {
                circleCell.setDropTargetState(false)
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
        // Final cleanup
    }
    
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath,
              let dragItem = coordinator.items.first,
              let sourceCircle = dragItem.dragItem.localObject as? Circle else {
            return
        }
        
        // Find the source index path
        guard let sourceIndexPath = circles.firstIndex(where: { $0.id == sourceCircle.id }).map({ IndexPath(item: $0, section: 0) }) else {
            return
        }
        
        // Perform the reorder
        handleReorder(from: sourceIndexPath, to: destinationIndexPath, coordinator: coordinator)
    }
    
    // MARK: - Drop Handling Methods
    
    func handleReorder(from sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath, coordinator: UICollectionViewDropCoordinator) {
        // Safety check: only allow reordering for current user's own profile
        guard user?.id == AuthService.shared.getUserId() else {
            Logger.debug("❌ ProfileViewController: Attempted to reorder for non-current user")
            return
        }
        
        // Perform the reorder
        circlesCollectionView.performBatchUpdates({
            // Update circles array
            let movedCircle = circles.remove(at: sourceIndexPath.item)
            circles.insert(movedCircle, at: destinationIndexPath.item)
            
            // Move the item in the collection view
            circlesCollectionView.moveItem(at: sourceIndexPath, to: destinationIndexPath)
        }) { [weak self] _ in
            // Save the new order to the backend
            self?.saveCircleOrder()
        }
        
        // Handle the drop
        if let dragItem = coordinator.items.first?.dragItem {
            coordinator.drop(dragItem, toItemAt: destinationIndexPath)
        }
    }
    
    func reorderItems(coordinator: UICollectionViewDropCoordinator, destinationIndexPath: IndexPath, collectionView: UICollectionView) {
        if let item = coordinator.items.first,
           let sourceIndexPath = item.sourceIndexPath {
            
            collectionView.performBatchUpdates({
                // Update the data model
                let movedCircle = circles.remove(at: sourceIndexPath.item)
                circles.insert(movedCircle, at: destinationIndexPath.item)
                
                // Update the collection view
                collectionView.deleteItems(at: [sourceIndexPath])
                collectionView.insertItems(at: [destinationIndexPath])
            }) { [weak self] _ in
                // Save the new order to the backend
                self?.saveCircleOrder()
            }
            
            coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
        }
    }
    
    func saveCircleOrder() {
        // Safety check: only allow saving for current user
        guard user?.id == AuthService.shared.getUserId() else {
            Logger.debug("❌ ProfileViewController: Attempted to save circle order for non-current user")
            return
        }
        
        // Extract the circle IDs in their new order
        let circleIds = circles.map { $0.id }
        
        // Call the API to save the new order
        UserService.shared.reorderCircles(circleIds: circleIds) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                Logger.debug("Failed to save circle order: \(error)")
                // Optionally reload circles to restore original order
                self.loadUserCircles()
            } else {
                Logger.debug("Circle order saved successfully")
            }
        }
    }
    
    func loadUserCircles() {
        guard let userId = user?.id else { return }
        
        // Fetch circles (same logic as in fetchUserStats)
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let circles):
                    self.circles = circles
                    self.circlesStatView.configure(number: "\(circles.count)", title: "Circles")
                    self.circlesCollectionView.reloadData()
                    self.updateCollectionViewHeight()
                    
                    // Load all places for search functionality
                    self.loadAllPlacesFromCircles(circles)
                case .failure:
                    self.circles = []
                    self.allPlaces = []
                    self.circlesStatView.configure(number: "0", title: "Circles")
                    self.circlesCollectionView.reloadData()
                    self.updateCollectionViewHeight()
                }
            }
        }
    }
    
    func removeDuplicatePlaces(_ places: [Place]) -> [Place] {
        var seenPlaceIds = Set<String>()
        var deduplicatedPlaces: [Place] = []
        var duplicatesFound = 0
        
        for place in places {
            if !seenPlaceIds.contains(place.id) {
                seenPlaceIds.insert(place.id)
                deduplicatedPlaces.append(place)
            } else {
                duplicatesFound += 1
                Logger.debug("🔍 ProfileViewController - Skipping duplicate place: '\(place.name)' (ID: \(place.id))")
            }
        }
        
        if duplicatesFound > 0 {
            Logger.debug("⚠️ ProfileViewController - Found and removed \(duplicatesFound) duplicate places")
        }
        
        return deduplicatedPlaces
    }
    
    func loadAllPlacesFromCircles(_ circles: [Circle]) {
        Logger.debug("🔍 [Places Debug] loadAllPlacesFromCircles called with \(circles.count) circles")
        allPlaces.removeAll()
        let dispatchGroup = DispatchGroup()
        
        for circle in circles {
            Logger.debug("🔍 [Places Debug] Loading places for circle: \(circle.name) (id: \(circle.id))")
            dispatchGroup.enter()
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { [weak self] result in
                guard let self = self else { 
                    dispatchGroup.leave()
                    return 
                }
                
                switch result {
                case .success(let places):
                    Logger.debug("🔍 [Places Debug] Loaded \(places.count) places from circle: \(circle.name)")
                    DispatchQueue.main.async {
                        self.allPlaces.append(contentsOf: places)
                    }
                case .failure(let error):
                    Logger.debug("⚠️ [Places Debug] Failed to fetch places for circle \(circle.name): \(error)")
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            Logger.debug("🔍 [Places Debug] All circles processed, total raw places: \(self.allPlaces.count)")
            
            // Log some sample places and their categories
            if !self.allPlaces.isEmpty {
                Logger.debug("🔍 [Places Debug] Sample places and categories:")
                for (index, place) in self.allPlaces.prefix(3).enumerated() {
                    Logger.debug("  \(index + 1). \(place.name) - Category: \(place.category.rawValue), Custom: \(place.customCategoryId ?? "none")")
                }
            }
            
            // Deduplicate places that might exist in multiple circles
            let deduplicatedPlaces = self.removeDuplicatePlaces(self.allPlaces)
            self.allPlaces = deduplicatedPlaces
            
            // Update available categories based on loaded places
            self.updateAvailableCategories()
            
            Logger.debug("🔍 ProfileViewController - Loaded \(self.allPlaces.count) total unique places for search (after deduplication)")
            // Update map with all places by default
            self.filterPlaces()
        }
    }
    
    func updateAvailableCategories() {
        Logger.debug("🔍 [Categories Debug] updateAvailableCategories called with \(allPlaces.count) places")
        
        // Get unique categories from all places, including custom categories
        availableCategories = PlaceCategory.uniqueCategories(from: allPlaces)
        
        Logger.debug("🔍 [Categories Debug] Found \(availableCategories.count) unique categories:")
        for (index, category) in availableCategories.enumerated() {
            Logger.debug("  \(index + 1). \(category.displayName) (\(category.isCustom ? "custom" : "standard"))")
        }
        
        // The hamburger chip's menu rebuilds itself on every open, so no
        // explicit menu refresh is needed here
    }
}

