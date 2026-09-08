import UIKit

// MARK: - Place Text Matching
extension Place {
    /// One matcher for the search overlay AND the map-pin search filter, so
    /// the results list and the pins can never disagree about what "matches".
    /// Typo-tolerant: "piza" finds "pizza" — a query word of 4+ characters may
    /// be one edit away from a word (or word prefix) in the place's text, two
    /// edits for 8+ characters. Exact substring containment stays the fast
    /// path, so nothing that matched before stops matching.
    func matches(searchQuery query: String) -> Bool {
        let haystack = Self.fold(
            [name, address, description ?? "", notes ?? "", publicNotes ?? "", privateNotes ?? ""]
                .joined(separator: " ")
        )
        let needle = Self.fold(query)
        guard !needle.isEmpty else { return true }
        if haystack.contains(needle) { return true }

        // Every query word must appear somewhere — as a substring, or within
        // typo distance of some word in the text.
        let tokens = needle.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !tokens.isEmpty else { return false }
        let words = haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return tokens.allSatisfy { token in
            haystack.contains(token) || words.contains { Self.fuzzyMatch(token: token, word: $0) }
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// True when `token` is within typo distance of `word`, or of `word`'s
    /// prefix of the same length (so partially-typed words tolerate typos
    /// too: "piza" matches "pizzeria" via its "pizz" prefix).
    private static func fuzzyMatch(token: String, word: String) -> Bool {
        let n = token.count
        guard n >= 4 else { return false } // short words: exact only, too noisy
        let allowed = n >= 8 ? 2 : 1
        if abs(word.count - n) <= allowed,
           boundedEditDistance(token, word, limit: allowed) <= allowed {
            return true
        }
        if word.count > n,
           boundedEditDistance(token, String(word.prefix(n)), limit: allowed) <= allowed {
            return true
        }
        return false
    }

    /// Levenshtein distance, bailing out with limit+1 as soon as the limit is
    /// unreachable — keeps per-keystroke filtering cheap over large sets.
    private static func boundedEditDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let s = Array(a.unicodeScalars), t = Array(b.unicodeScalars)
        if abs(s.count - t.count) > limit { return limit + 1 }
        var previous = Array(0...t.count)
        var current = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            current[0] = i
            var rowMin = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[t.count]
    }
}

// MARK: - PlaceSearchable Protocol
protocol PlaceSearchable: UIViewController, UISearchBarDelegate {
    var allPlaces: [Place] { get set }
    var filteredPlaces: [Place] { get set }
    var isSearching: Bool { get set }
    var searchResultsTableView: UITableView { get }
    var searchResultsHeightConstraint: NSLayoutConstraint? { get set }
    var searchBar: UISearchBar { get }
    
    // Optional: For getting circles to show in search results
    var circles: [Circle] { get }
    
    func showSearchResults()
    func hideSearchResults()
    func filterPlaces(searchText: String)
    func navigateToPlace(_ place: Place)
}

// MARK: - Default Implementations
extension PlaceSearchable {
    
    func showSearchResults() {
        let maxVisibleResults = 5
        let cellHeight: CGFloat = 60
        let numberOfResults = min(filteredPlaces.count, maxVisibleResults)
        let height = CGFloat(numberOfResults) * cellHeight
        
        searchResultsTableView.isHidden = false
        searchResultsHeightConstraint?.constant = height
        
        UIView.animate(withDuration: 0.3) {
            self.searchResultsTableView.alpha = 1
            self.view.layoutIfNeeded()
        }
        
        searchResultsTableView.reloadData()
    }
    
    func hideSearchResults() {
        UIView.animate(withDuration: 0.3) {
            self.searchResultsTableView.alpha = 0
            self.searchResultsHeightConstraint?.constant = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.searchResultsTableView.isHidden = true
        }
    }
    
    func filterPlaces(searchText: String) {
        filteredPlaces = allPlaces.filter { $0.matches(searchQuery: searchText) }
    }
}

// MARK: - UISearchBarDelegate Default Implementation
extension PlaceSearchable {
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            isSearching = false
            filteredPlaces = []
            hideSearchResults()
        } else {
            isSearching = true
            filterPlaces(searchText: searchText)
            
            if !filteredPlaces.isEmpty {
                showSearchResults()
            } else {
                hideSearchResults()
            }
        }
        
        // Let each view controller handle its own empty state updates
        // by overriding this method if needed
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        filteredPlaces = []
        hideSearchResults()
        
        // Let each view controller handle its own empty state updates
        // by overriding this method if needed
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }
}

// MARK: - Search Results Table View Default Implementation
extension PlaceSearchable {
    
    func numberOfRowsInSearchResults() -> Int {
        return isSearching ? filteredPlaces.count : 0
    }
    
    // Default implementation - can be overridden by conforming classes
    func configureSearchResultCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard indexPath.row < filteredPlaces.count else { return }
        
        let place = filteredPlaces[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = place.name
        
        // Show address and circle name if available
        if let circleId = place.circleId, let circle = circles.first(where: { $0.id == circleId }) {
            content.secondaryText = "\(place.address) • \(circle.name)"
        } else {
            content.secondaryText = place.address
        }
        
        content.image = UIImage(systemName: "mappin.circle.fill")
        content.imageProperties.tintColor = Constants.Colors.primary
        
        cell.contentConfiguration = content
    }
    
    func handleSearchResultSelection(at indexPath: IndexPath) {
        guard indexPath.row < filteredPlaces.count else { return }
        
        let place = filteredPlaces[indexPath.row]
        
        // Clear search
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        filteredPlaces = []
        hideSearchResults()
        
        // Navigate to place (each controller implements this differently)
        navigateToPlace(place)
    }
}