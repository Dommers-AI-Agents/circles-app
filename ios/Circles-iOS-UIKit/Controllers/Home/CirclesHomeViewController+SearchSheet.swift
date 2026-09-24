import UIKit

// The home search results sheet: how it is installed, how the map makes room
// for it, how it follows the keyboard, and the rule that nothing reloads
// under a finger. The rows themselves are still drawn by +TableView.

// MARK: - Install & layout
extension CirclesHomeViewController {
    func installSearchResultsSheet() {
        // Below the loading overlay, above everything else on `view`.
        view.insertSubview(searchResultsSheet, belowSubview: loadingContainerView)
        searchResultsSheet.install(in: view, bottomAnchor: view.keyboardLayoutGuide.topAnchor)
        searchResultsSheet.tableView.delegate = self
        searchResultsSheet.tableView.dataSource = self
        searchResultsSheet.onStateChange = { [weak self] state in
            self?.isSearchSheetCollapsed = (state == .collapsed)
        }
        searchResultsSheet.onHandleTap = { [weak self] in
            guard let self else { return }
            if self.isSearchSheetCollapsed {
                self.expandSearchSheet()          // no keyboard: the handle is not the bar
            } else {
                self.collapseSearchSheet()
            }
        }
    }

    /// Room between the mode control and the keyboard (or the safe-area
    /// bottom when there is none); the sheet takes about half of it.
    func searchSheetAvailableHeight(keyboardTop: CGFloat? = nil) -> CGFloat {
        view.layoutIfNeeded()
        let safeBottom = view.bounds.maxY - view.safeAreaInsets.bottom
        let top = min(keyboardTop ?? view.keyboardLayoutGuide.layoutFrame.minY, safeBottom)
        let above = searchModeControl.isHidden ? searchBar.frame.maxY : searchModeControl.frame.maxY
        return max(top - (above + 8), 0)
    }

    /// Lifts the map under the mode control and runs it to the bottom of the
    /// screen so it stays visible above the sheet; the people row and the
    /// map's own list toggle step aside. Idempotent.
    func enterSearchLayout() {
        guard !isSearchLayoutActive else { return }
        isSearchLayoutActive = true
        resetPlacesListToMap()
        setSearchModeControlVisible(true)
        scrollView.setContentOffset(.zero, animated: false)
        scrollView.isScrollEnabled = false
        mapHeightConstraint?.isActive = false
        mapTopToPeopleRowConstraint.isActive = false
        mapTopSearchingConstraint.isActive = true
        mapBottomSearchingConstraint.isActive = true
        userListView.isHidden = true
        listToggleButton.isHidden = true
        mapPlaceCountLabel.isHidden = true
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    /// The home screen as it was before the search. Idempotent.
    func exitSearchLayout() {
        guard isSearchLayoutActive else { return }
        isSearchLayoutActive = false
        mapTopSearchingConstraint.isActive = false
        mapBottomSearchingConstraint.isActive = false
        mapTopToPeopleRowConstraint.isActive = true
        applyMapHeightForCurrentMode()
        scrollView.isScrollEnabled = true
        userListView.isHidden = false
        userListView.alpha = 1
        listToggleButton.isHidden = false
        mapPlaceCountLabel.isHidden = isShowingPlacesList
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    /// The mode control belongs to an active search — it appears with the
    /// first keystroke and goes away with Cancel, so the home screen is
    /// unchanged for anyone not searching.
    func setSearchModeControlVisible(_ visible: Bool) {
        searchModeControl.isHidden = !visible
    }
}

// MARK: - Show / hide / collapse
extension CirclesHomeViewController {
    /// Everything that changes what the sheet should show calls this. A
    /// collapsed sheet stays collapsed — late async results must not yank
    /// the map away again.
    func refreshSearchOverlay() {
        if isSearching && searchPlan.hasRows {
            showSearchResults()
        } else {
            hideSearchResults()
        }
    }

    func showSearchResults() {
        enterSearchLayout()
        let plan = searchPlan
        searchResultsSheet.present(state: isSearchSheetCollapsed ? .collapsed : .expanded,
                                   availableHeight: searchSheetAvailableHeight())
        searchResultsSheet.setContent(plan: plan, title: plan.handleTitle)
    }

    /// Sheet gone. When the search itself is over (every teardown path sets
    /// `isSearching = false` first) the home layout comes back too; a live
    /// query with no rows keeps the search layout — the map, with "No results
    /// found", is the answer.
    func hideSearchResults() {
        searchResultsSheet.hide()
        if !isSearching { exitSearchLayout() }
    }

    /// Tap on the map, pull the list down, or tap the handle: the sheet drops
    /// to its handle line and the keyboard goes; pins stay filtered.
    func collapseSearchSheet() {
        guard isSearching, !isSearchSheetCollapsed else { return }
        isSearchSheetCollapsed = true
        searchBar.resignFirstResponder()
        searchResultsSheet.setState(.collapsed, animated: true)
    }

    func expandSearchSheet() {
        guard isSearching, isSearchSheetCollapsed else { return }
        isSearchSheetCollapsed = false
        refreshSearchOverlay()
    }

    func refitSearchSheet() {
        guard isSearching, searchResultsSheet.isVisible else { return }
        searchResultsSheet.updateAvailableHeight(searchSheetAvailableHeight(), duration: 0.2, options: [.curveEaseOut])
    }
}

// MARK: - Keyboard
extension CirclesHomeViewController {
    func observeKeyboardForSearchSheet() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(searchSheetKeyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
    }

    /// The sheet's bottom edge rides the keyboard layout guide on its own;
    /// its height re-fits the new room in the keyboard's own animation.
    @objc func searchSheetKeyboardWillChangeFrame(_ note: Notification) {
        guard isSearching, view.window != nil, let info = note.userInfo,
              let end = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let keyboardTop = view.convert(end, from: nil).minY
        searchResultsSheet.updateAvailableHeight(searchSheetAvailableHeight(keyboardTop: keyboardTop),
                                                 duration: duration,
                                                 options: UIView.AnimationOptions(rawValue: curve << 16))
    }
}

// MARK: - Nothing moves under a finger
extension CirclesHomeViewController {
    func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath) {
        guard tableView == searchResultsTableView else { return }
        searchResultsSheet.setRowHighlighted(true)
    }

    func tableView(_ tableView: UITableView, didUnhighlightRowAt indexPath: IndexPath) {
        guard tableView == searchResultsTableView else { return }
        searchResultsSheet.setRowHighlighted(false)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView == searchResultsTableView, !decelerate else { return }
        searchResultsSheet.flushPendingUpdateIfIdle()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView == searchResultsTableView else { return }
        searchResultsSheet.flushPendingUpdateIfIdle()
    }

    /// Pulling the list down past its top is "give me the map".
    func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                   withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scrollView == searchResultsTableView else { return }
        if SearchSheetDetentResolver.shouldCollapse(forPullDownOffset: scrollView.contentOffset.y) {
            collapseSearchSheet()
        }
    }
}
