import UIKit

/// After a store posts a new offer, announcement or event (Wes, 2026-11-09):
/// one sheet — who it alerted, then "Share to Instagram story" / "Share as a
/// post" / "Not now". The card is StorePostCard over the store's photo.
enum StorePostShareController {

    static func offer(post: StorePost, alertedLine: String?, venueName: String, placeId: String?, from presenter: UIViewController) {
        AlertPresenter.showActionSheet(
            title: StorePostCopy.sheetTitle(post),
            message: StorePostCopy.sheetMessage(alertedLine: alertedLine),
            actions: [
                (title: StorePostCopy.shareStory, style: .default, handler: { share(.story, post: post, venueName: venueName, placeId: placeId, from: presenter) }),
                (title: StorePostCopy.sharePost, style: .default, handler: { share(.post, post: post, venueName: venueName, placeId: placeId, from: presenter) }),
                (title: StorePostCopy.notNow, style: .cancel, handler: {})
            ],
            from: presenter
        )
    }

    private static func share(_ format: StorePostCard.Format, post: StorePost, venueName: String, placeId: String?, from presenter: UIViewController) {
        let loading = AlertPresenter.showLoading(from: presenter)
        loadPhoto(placeId: placeId) { photo in
            let image = StorePostCard.render(format, photo: photo, storeName: venueName,
                                             headline: StorePostCopy.headline(post),
                                             detail: StorePostCopy.detail(post, storeName: venueName),
                                             footer: StorePostCopy.footer(post))
            loading.dismiss(animated: true) {
                switch format {
                case .story:
                    if !InstagramShare.shareToStory(image) {
                        AlertPresenter.showAlert(title: "Instagram", message: StorePostCopy.instagramMissing,
                                                 actions: [(title: "OK", style: .default, handler: { InstagramShare.sharePost(image, from: presenter) })],
                                                 from: presenter)
                    }
                case .post:
                    InstagramShare.sharePost(image, from: presenter)
                }
            }
        }
    }

    /// The store's cover (or first) photo; nil → the brand-blue card
    private static func loadPhoto(placeId: String?, completion: @escaping (UIImage?) -> Void) {
        guard let placeId else { return completion(nil) }
        PlaceService.shared.fetchPlaceById(id: placeId) { result in
            guard case .success(let place) = result, let url = place.photos?.first, !url.isEmpty else {
                return DispatchQueue.main.async { completion(nil) }
            }
            ImageService.shared.loadImage(from: url) { image in
                DispatchQueue.main.async { completion(image) }
            }
        }
    }
}
