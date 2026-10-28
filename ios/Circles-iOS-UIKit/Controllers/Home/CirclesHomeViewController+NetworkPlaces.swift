import UIKit
import CoreLocation

// The network's places for search, moved out of +Search so that file stays
// about the search bar.
//
// This used to fetch EVERY network circle's places (one request per circle —
// 239 for a large network) and fold them in only when the last one answered,
// so a place a connection saved joined the results 15–30 s after typing and
// the burst slowed every other call. Now one request per query: the server
// matches the text against the venue catalog and returns the network's saves
// of those venues (GET /network/places/search; Wes, 2026-10-28).
extension CirclesHomeViewController {
    /// Fetches the network's saves whose venue matches `query` and folds them
    /// into `networkPlaces`, then re-matches the current search. Debounced by
    /// the caller; stale answers (the text moved on) are dropped.
    func loadNetworkPlaces(matching query: String, reference: CLLocation?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Logger.debug("🔍 Searching network places for \"\(trimmed)\"")

        PlaceService.shared.searchNetworkPlaces(query: trimmed, near: reference) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success(let places) = result else {
                    Logger.debug("Network place search failed: \(result)")
                    return
                }
                // Results accumulate across queries (dedupe by id), so backing
                // up the text still matches what an earlier query brought in
                self.networkPlaces = self.removeDuplicatePlaces(self.networkPlaces + places)
                Logger.debug("🔍 Network search \"\(trimmed)\": \(places.count) places, \(self.networkPlaces.count) cached")

                guard self.isSearching,
                      self.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                // Same query, same origin: re-match, don't re-fetch suggestions
                self.filterPlaces(searchText: trimmed, refetchSuggestions: false)
                self.mapViewController?.setSearchFilter(self.searchMode.filtersMap(trimmed),
                                                        matchedPlaceIds: self.searchMode == .places ? self.appleMatchedPlaceIds : [])
                self.refreshSearchOverlay()
                self.updateEmptyState()
            }
        }
    }
}
