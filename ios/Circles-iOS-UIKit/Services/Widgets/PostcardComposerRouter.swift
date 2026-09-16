import UIKit
import FavWidgetsCore

/// Anything with a photo → postcard. Lands on the Widgets tab's postcard page
/// with that photo already chosen and the place it came from as the caption
/// place. Works from anywhere: the home Moments tab and place detail (already
/// inside a nav stack), the fullscreen player (presented modally from Profile
/// or a deep link), and the add-place flow — a modal presenter is dismissed
/// first either way.
///
/// The composer takes a picture or nothing, so every entry point has to supply
/// one; `open(photoUrl:)` is the branch for callers that only hold a URL.
enum PostcardComposerRouter {
    static func open(reel: PlaceVideo, cachedPhoto: UIImage?, from presenter: UIViewController) {
        let place = WidgetPlaceRef(id: reel.placeId, name: reel.placeName, isGlobal: false)
        if let photo = cachedPhoto {
            route(photo: photo, place: place, from: presenter)
            return
        }
        // The cell hadn't finished loading the image yet — fetch it once more
        // (cached by ImageService) rather than opening an empty composer
        open(photoUrl: reel.thumbnailUrl, place: place, from: presenter,
             unavailableMessage: "This moment's photo isn't available.")
    }

    /// A place the user saved — its own photo becomes the card.
    static func open(place: Place, from presenter: UIViewController) {
        open(photoUrl: place.photos?.first,
             place: widgetPlace(for: place),
             from: presenter,
             unavailableMessage: "This place doesn't have a photo to put on a card yet.")
    }

    /// The photo is already in hand (the one the user just picked for a save).
    static func open(photo: UIImage, place: Place, from presenter: UIViewController) {
        route(photo: photo, place: widgetPlace(for: place), from: presenter)
    }

    static func open(photoUrl: String?, place: WidgetPlaceRef?, from presenter: UIViewController,
                     unavailableMessage: String = "That photo isn't available.") {
        guard let url = photoUrl, !url.isEmpty else {
            AlertPresenter.showError(message: unavailableMessage, from: presenter)
            return
        }
        let loading = AlertPresenter.showLoading(message: "Loading photo...", from: presenter)
        ImageService.shared.loadImage(from: url) { image in
            DispatchQueue.main.async {
                loading.dismiss(animated: false) {
                    guard let image = image else {
                        AlertPresenter.showError(message: unavailableMessage, from: presenter)
                        return
                    }
                    route(photo: image, place: place, from: presenter)
                }
            }
        }
    }

    /// The canonical venue id when the save has one: `HomeWidgetsPostcardSender`
    /// only forwards a `globalPlaceId` for a ref marked global, and that's what
    /// ties the card to the venue everyone else sees.
    static func widgetPlace(for place: Place) -> WidgetPlaceRef {
        if let global = place.globalPlaceId, !global.isEmpty {
            return WidgetPlaceRef(id: global, name: place.name, isGlobal: true)
        }
        return WidgetPlaceRef(id: place.id, name: place.name, isGlobal: false)
    }

    private static func route(photo: UIImage, place: WidgetPlaceRef?, from presenter: UIViewController) {
        guard let tabBar = tabBarController(near: presenter) else { return }

        let land = {
            tabBar.selectedIndex = 0 // Home
            guard let nav = tabBar.viewControllers?.first as? UINavigationController,
                  let home = nav.viewControllers.first as? CirclesHomeViewController else { return }
            nav.popToRootViewController(animated: false)
            home.openPostcardComposer(photo: photo, place: place)
        }

        // The fullscreen player is a modal; get it out of the way first
        if presenter.presentingViewController != nil {
            presenter.dismiss(animated: true, completion: land)
        } else {
            land()
        }
    }

    private static func tabBarController(near presenter: UIViewController) -> CirclesTabBarController? {
        if let tabBar = presenter.view.window?.rootViewController as? CirclesTabBarController { return tabBar }
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow })?.rootViewController as? CirclesTabBarController }
            .first
    }
}
