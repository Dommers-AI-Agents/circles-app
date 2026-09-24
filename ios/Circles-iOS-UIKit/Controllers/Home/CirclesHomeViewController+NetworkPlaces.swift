import UIKit

// Loading the network's places for search (every connection's visible saves),
// moved out of +Search so that file stays about the search bar.
extension CirclesHomeViewController {
    // Load network places for search
    func loadNetworkPlaces() {
        guard !isLoadingNetworkPlaces else { return }
        
        isLoadingNetworkPlaces = true
        Logger.debug("🔍 Loading network places for search...")
        
        let group = DispatchGroup()
        var allNetworkPlaces: [Place] = []
        
        // If we don't have network circles, fetch them first
        if networkCircles.isEmpty {
            group.enter()
            APIService.shared.request(
                endpoint: "network/my-network-circles",
                method: .get,
                requiresAuth: true
            ) { [weak self] (result: Result<CirclesDataResponse, APIError>) in
                switch result {
                case .success(let response):
                    self?.networkCircles = response.data
                    // Now fetch places from network circles
                    for circle in response.data {
                        group.enter()
                        PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                            switch result {
                            case .success(let places):
                                allNetworkPlaces.append(contentsOf: places)
                            case .failure(let error):
                                Logger.debug("Failed to fetch places for network circle \(circle.id): \(error)")
                            }
                            group.leave()
                        }
                    }
                case .failure(let error):
                    Logger.debug("Failed to fetch network circles: \(error)")
                }
                group.leave()
            }
        } else {
            // Use existing network circles
            for circle in networkCircles {
                group.enter()
                PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                    switch result {
                    case .success(let places):
                        allNetworkPlaces.append(contentsOf: places)
                    case .failure(let error):
                        Logger.debug("Failed to fetch places for network circle \(circle.id): \(error)")
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoadingNetworkPlaces = false
            
            // Deduplicate network places before storing
            let deduplicatedNetworkPlaces = self.removeDuplicatePlaces(allNetworkPlaces)
            self.networkPlaces = deduplicatedNetworkPlaces
            Logger.debug("🔍 Loaded \(allNetworkPlaces.count) raw network places, deduplicated to \(deduplicatedNetworkPlaces.count) unique places for search")
            
            // If a search is active, fold the newly-loaded network places into
            // the current results
            if self.isSearching, let text = self.searchBar.text, !text.isEmpty {
                self.filterPlaces(searchText: text)
                self.refreshSearchOverlay()
                self.updateEmptyState()
            }
        }
    }
}
