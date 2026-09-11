import UIKit
import MapKit
import UniformTypeIdentifiers

// The circle's places table for CircleDetailViewController: data source,
// selection, swipe/context actions, delete + move-to-circle, drag/drop
// reorder, and the export builders' entry points. Moved verbatim from the
// core controller (Phase 5, circle-detail step 6).

// MARK: - UITableViewDelegate & UITableViewDataSource
extension CircleDetailViewController: UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredPlaces.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell", for: indexPath) as? PlaceTableViewCell else {
            return UITableViewCell()
        }
        
        let place = filteredPlaces[indexPath.row]
        cell.configure(with: place)
        
        // Set up share button action
        cell.onShareTapped = { [weak self] place in
            self?.sharePlace(place)
        }
        
        // Set up directions button action
        cell.onDirectionsTapped = { [weak self] place in
            self?.openPlaceInMaps(place)
        }
        
        // Set up like button action
        cell.onLikeTapped = { [weak self] place in
            self?.likePlace(place)
        }
        
        // Set up comment button action
        cell.onCommentTapped = { [weak self] place in
            self?.showComments(for: place)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let place = filteredPlaces[indexPath.row]
        
        // Debug logging
        Logger.debug("🔍 CircleDetailViewController - Selected place:")
        Logger.debug("  - Place name: \(place.name)")
        Logger.debug("  - Place ID: \(place.id)")
        Logger.debug("  - Has photos: \(place.hasPhotos)")
        Logger.debug("  - Photos array: \(place.photos ?? [])")
        Logger.debug("  - Photos count: \(place.photos?.count ?? 0)")
        
        // Mark place as viewed if it's new
        if place.isNew == true {
            NetworkManager.shared.markPlaceAsViewed(placeId: place.id, circleId: circle.id) { error in
                if let error = error {
                    Logger.debug("Error marking place as viewed: \(error)")
                } else {
                    Logger.debug("Successfully marked place as viewed")
                }
            }
        }
        
        let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
    
    // MARK: - Swipe Actions
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Only allow actions if user can edit
        guard circle.canEdit else { return nil }
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.confirmDeletePlace(at: indexPath, completion: completion)
        }
        deleteAction.image = UIImage(systemName: "trash")
        
        let moveAction = UIContextualAction(style: .normal, title: "Move") { [weak self] _, _, completion in
            self?.movePlaceToCircle(at: indexPath)
            completion(true)
        }
        moveAction.image = UIImage(systemName: "arrow.right.circle")
        moveAction.backgroundColor = .systemBlue
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction, moveAction])
        configuration.performsFirstActionWithFullSwipe = false

        return configuration
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        // Long-press menu mirroring the swipe actions
        guard circle.canEdit else { return nil }
        let place = filteredPlaces[indexPath.row]

        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
            let moveAction = UIAction(
                title: "Move to Another Circle",
                image: UIImage(systemName: "arrow.right.circle")
            ) { _ in
                self?.movePlaceToCircle(at: indexPath)
            }

            let deleteAction = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.confirmDeletePlace(at: indexPath) { _ in }
            }

            return UIMenu(title: place.name, children: [moveAction, deleteAction])
        }
    }

    private func confirmDeletePlace(at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
        let place = filteredPlaces[indexPath.row]
        
        let alert = UIAlertController(
            title: "Delete Place",
            message: "Are you sure you want to remove \"\(place.name)\" from this circle?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deletePlace(at: indexPath)
            completion(true)
        })
        
        present(alert, animated: true)
    }
    
    private func deletePlace(at indexPath: IndexPath) {
        let place = filteredPlaces[indexPath.row]
        
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Deleting", message: "Removing place...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        PlaceService.shared.deletePlace(id: place.id) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        // Remove from local arrays
                        if let originalIndex = self?.places.firstIndex(where: { $0.id == place.id }) {
                            self?.places.remove(at: originalIndex)
                        }
                        if let filteredIndex = self?.filteredPlaces.firstIndex(where: { $0.id == place.id }) {
                            self?.filteredPlaces.remove(at: filteredIndex)
                        }
                        
                        // Update table view
                        self?.tableView.deleteRows(at: [indexPath], with: .fade)
                        
                        // Update map
                        self?.addAnnotationsToMap()
                        
                        // Update table view height after deletion
                        self?.updateTableViewHeight()
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Failed to delete place: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(errorAlert, animated: true)
                    }
                }
            }
        }
    }
    
    private func movePlaceToCircle(at indexPath: IndexPath) {
        let place = filteredPlaces[indexPath.row]
        
        // Create and present circle selection view controller
        let circleSelectionVC = CircleSelectionViewController(excludedCircleId: circle.id)
        circleSelectionVC.delegate = self
        circleSelectionVC.placeToMove = place
        
        let navController = UINavigationController(rootViewController: circleSelectionVC)
        present(navController, animated: true)
    }
    
    // MARK: - CircleSelectionWithPlaceDelegate
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle, forPlace place: Place) {
        controller.dismiss(animated: true) {
            self.performMovePlace(place, to: circle)
        }
    }
    
    // MARK: - CircleSelectionDelegate (base protocol)
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle) {
        // This shouldn't be called when using placeToMove, but implement for protocol compliance
        controller.dismiss(animated: true)
    }
    
    func circleSelectionViewControllerDidCancel(_ controller: CircleSelectionViewController) {
        controller.dismiss(animated: true)
    }
    
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didCreateNewCircle circle: Circle, forPlace place: Place) {
        controller.dismiss(animated: true) {
            self.performMovePlace(place, to: circle)
        }
    }
    
    private func performMovePlace(_ place: Place, to targetCircle: Circle) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Moving Place", message: "Moving \(place.name) to \(targetCircle.name)...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Perform the move
        PlaceService.shared.movePlaceToCircle(placeId: place.id, targetCircleId: targetCircle.id) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        // Remove from local arrays
                        if let originalIndex = self.places.firstIndex(where: { $0.id == place.id }) {
                            self.places.remove(at: originalIndex)
                        }
                        if let filteredIndex = self.filteredPlaces.firstIndex(where: { $0.id == place.id }) {
                            self.filteredPlaces.remove(at: filteredIndex)
                            
                            // Update table view
                            if filteredIndex < self.tableView.numberOfRows(inSection: 0) {
                                self.tableView.deleteRows(at: [IndexPath(row: filteredIndex, section: 0)], with: .fade)
                            } else {
                                self.tableView.reloadData()
                            }
                        }
                        
                        // Update map
                        self.addAnnotationsToMap()
                        
                        // Update table view height after removal
                        self.updateTableViewHeight()
                        
                        // Show success message
                        let successAlert = UIAlertController(
                            title: "Success",
                            message: "\(place.name) has been moved to \(targetCircle.name)",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(successAlert, animated: true)
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Failed to move place: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Drag Delegate
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // Disable drag when filtering (category or tag) — row indexes would
        // not map back to the circle's true place order
        guard selectedCategory == nil, selectedTag == nil else { return [] }
        
        // Only allow drag if user can edit the circle
        guard circle.canEdit else { return [] }
        
        let place = filteredPlaces[indexPath.row]
        let itemProvider = NSItemProvider(object: place.id as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = place
        return [dragItem]
    }
    
    // MARK: - Drop Delegate
    func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
        return session.hasItemsConforming(toTypeIdentifiers: [UTType.text.identifier])
    }
    
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        if tableView.hasActiveDrag {
            if session.items.count > 1 {
                return UITableViewDropProposal(operation: .cancel)
            } else {
                return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
            }
        } else {
            return UITableViewDropProposal(operation: .forbidden)
        }
    }
    
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath else { return }
        
        for item in coordinator.items {
            guard let sourceIndexPath = item.sourceIndexPath else { continue }
            
            tableView.performBatchUpdates({
                let movedPlace = places.remove(at: sourceIndexPath.row)
                places.insert(movedPlace, at: destinationIndexPath.row)
                tableView.moveRow(at: sourceIndexPath, to: destinationIndexPath)
            })
            
            coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
            
            // Update the order in the backend
            updatePlaceOrder()
        }
    }
    
    // MARK: - Export Methods
    
    func exportAsPDF() {
        let data = CircleExporter.pdf(circleName: circle.name, places: places)
        shareExportedFile(data: data, filename: "\(circle.name).pdf", mimeType: "application/pdf")
    }

    func exportAsCSV() {
        if let data = CircleExporter.csv(places: places).data(using: .utf8) {
            shareExportedFile(data: data, filename: "\(circle.name).csv", mimeType: "text/csv")
        }
    }

    func exportAsText() {
        if let data = CircleExporter.text(circleName: circle.name, places: places).data(using: .utf8) {
            shareExportedFile(data: data, filename: "\(circle.name).txt", mimeType: "text/plain")
        }
    }

    private func shareExportedFile(data: Data, filename: String, mimeType: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: tempURL)
            
            let activityViewController = UIActivityViewController(
                activityItems: [tempURL],
                applicationActivities: nil
            )
            
            // Exclude some activities
            activityViewController.excludedActivityTypes = [
                .assignToContact,
                .addToReadingList,
                .openInIBooks
            ]
            
            // For iPad
            if let popover = activityViewController.popoverPresentationController {
                popover.barButtonItem = navigationItem.rightBarButtonItems?.first { $0.action == #selector(exportButtonTapped) }
            }
            
            present(activityViewController, animated: true)
            
        } catch {
            showError("Failed to export file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper method to update place order
    private func updatePlaceOrder() {
        // Update the order of places in the backend
        Task {
            do {
                // Create an array of place IDs in the new order
                let orderedPlaceIds = places.map { $0.id }
                
                // Call the API to update the order
                try await PlaceService.shared.updatePlaceOrder(circleId: circle.id, placeIds: orderedPlaceIds)
                
                // Update map annotations to reflect new order if needed
                await MainActor.run {
                    self.addAnnotationsToMap()
                }
            } catch {
                Logger.debug("Failed to update place order: \(error)")
                // Optionally, revert the changes if the API call fails
                await MainActor.run {
                    self.fetchPlaces()
                }
            }
        }
    }
}
