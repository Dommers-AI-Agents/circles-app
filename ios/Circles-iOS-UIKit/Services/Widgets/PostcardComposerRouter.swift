import UIKit
import FavWidgetsCore

/// Moments → postcard. Lands on the Widgets tab's postcard page with the
/// moment's photo already chosen and the moment's place as the caption
/// place. Works from anywhere a reel cell lives: the home Moments tab
/// (already inside the home stack) and the fullscreen player (presented
/// modally from Profile or a deep link), which is dismissed first.
enum PostcardComposerRouter {
    static func open(reel: PlaceVideo, cachedPhoto: UIImage?, from presenter: UIViewController) {
        if let photo = cachedPhoto {
            route(photo: photo, reel: reel, from: presenter)
            return
        }
        // The cell hadn't finished loading the image yet — fetch it once more
        // (cached by ImageService) rather than opening an empty composer
        guard let url = reel.thumbnailUrl, !url.isEmpty else {
            AlertPresenter.showError(message: "This moment's photo isn't available.", from: presenter)
            return
        }
        let loading = AlertPresenter.showLoading(message: "Loading photo...", from: presenter)
        ImageService.shared.loadImage(from: url) { image in
            DispatchQueue.main.async {
                loading.dismiss(animated: false) {
                    guard let image = image else {
                        AlertPresenter.showError(message: "This moment's photo isn't available.", from: presenter)
                        return
                    }
                    route(photo: image, reel: reel, from: presenter)
                }
            }
        }
    }

    private static func route(photo: UIImage, reel: PlaceVideo, from presenter: UIViewController) {
        let place = WidgetPlaceRef(id: reel.placeId, name: reel.placeName, isGlobal: false)
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
