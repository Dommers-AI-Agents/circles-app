import Foundation

// MARK: - People dropdown counts

extension CirclesHomeViewController {
    /// The embedded map only holds the selected person's places, so the home
    /// hands it every loaded place (yours and the network's, hidden circles
    /// and hidden sources left out) with the home map's whose-place rule. The
    /// map counts them in its view and ranks the people dropdown by them.
    func mapViewControllerPeoplePlaces(_ controller: FullScreenMapViewController) -> MapPeoplePlaces? {
        let context = placeFilterContext()
        let loaded = HomePlaceFilter.excludingHiddenOrigins(
            excludingHiddenCircles(HomeState.dedupe(state.userOwnPlaces + state.allPlaces)),
            hidden: context.hiddenOrigins, currentUserId: context.currentUserId)
        let owners = context.networkCircleOwners
        return MapPeoplePlaces(places: loaded,
                               author: { HomePlaceFilter.author(of: $0, networkCircleOwners: owners) })
    }
}
