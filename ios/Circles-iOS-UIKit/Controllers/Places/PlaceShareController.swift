import UIKit

/// Shares a place, a market or an event as ONE bubble (Wes, 2026-11-12):
/// a card with the key facts (PlaceShareCard) whose tap opens the place in
/// FavCircles. Every place share goes through here: the place page, a
/// circle's place menu and the Locals tab.
enum PlaceShareController {
    /// What a Google-only place needs to become a venue record
    struct MintDetails {
        let name: String
        let address: String?
        let lat: Double?
        let lng: Double?
        let category: PlaceCategory
    }

    static func share(place: Place, from viewController: UIViewController, barButtonItem: UIBarButtonItem? = nil) {
        let target = PlaceShareCopy.target(id: place.id, globalPlaceId: place.globalPlaceId,
                                           googlePlaceId: place.googlePlaceId, addedBy: place.addedBy)
        let coordinates = place.location?.coordinates ?? []
        let mint = MintDetails(name: place.name, address: place.address,
                               lat: coordinates.count == 2 ? coordinates[1] : nil,
                               lng: coordinates.count == 2 ? coordinates[0] : nil,
                               category: place.category)
        share(content: PlaceShareCopy.content(for: place), target: target, mint: mint,
              from: viewController, barButtonItem: barButtonItem)
    }

    static func share(market: FarmersMarket, from viewController: UIViewController, sourceView: UIView?) {
        let mint = MintDetails(name: market.name, address: market.address, lat: market.lat, lng: market.lng, category: .retail)
        share(content: PlaceShareCopy.content(for: market), target: PlaceShareCopy.target(for: market), mint: mint,
              from: viewController, sourceView: sourceView)
    }

    static func share(event: NearbyEvent, from viewController: UIViewController, sourceView: UIView?) {
        let mint = MintDetails(name: event.venueName ?? event.name, address: event.venueAddress,
                               lat: event.lat, lng: event.lng, category: .entertainment)
        share(content: PlaceShareCopy.content(for: event), target: PlaceShareCopy.target(for: event), mint: mint,
              from: viewController, sourceView: sourceView)
    }

    static func share(content: PlaceShareContent, target: PlaceShareTarget, mint: MintDetails?,
                      from viewController: UIViewController,
                      barButtonItem: UIBarButtonItem? = nil, sourceView: UIView? = nil) {
        let loading = AlertPresenter.showLoading(message: "Getting it ready...", from: viewController)
        let group = DispatchGroup()
        var url = ShareLinks.appStoreURL
        var photo: UIImage?

        group.enter()
        resolveLink(target, mint: mint) { resolved in
            url = resolved
            group.leave()
        }

        if let photoUrl = content.photoUrl {
            group.enter()
            // A slow photo never holds up the share: the card has a fallback
            var finished = false
            let finish: (UIImage?) -> Void = { image in
                DispatchQueue.main.async {
                    guard !finished else { return }
                    finished = true
                    photo = image
                    group.leave()
                }
            }
            ImageService.shared.loadImage(from: photoUrl, completion: finish)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { finish(nil) }
        }

        group.notify(queue: .main) {
            let card = PlaceShareCard.image(for: content, photo: photo)
            let item = LinkPreviewItem(url: url, title: content.title, image: card)
            loading.dismiss(animated: true) {
                let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
                if let popover = sheet.popoverPresentationController {
                    if let barButtonItem {
                        popover.barButtonItem = barButtonItem
                    } else {
                        popover.sourceView = sourceView ?? viewController.view
                        popover.sourceRect = (sourceView ?? viewController.view).bounds
                    }
                }
                viewController.present(sheet, animated: true)
            }
        }
    }

    /// The link that opens the place. A Google-only place gets its venue
    /// record made first (one per place: the server reuses an existing one);
    /// if that fails, the App Store link still gets them the app.
    private static func resolveLink(_ target: PlaceShareTarget, mint: MintDetails?,
                                    completion: @escaping (URL) -> Void) {
        switch target {
        case .place(let id):
            completion(ShareLinks.place(id: id))
        case .appStore:
            completion(ShareLinks.appStoreURL)
        case .mint(let googlePlaceId):
            guard let mint, let lat = mint.lat, let lng = mint.lng,
                  let address = mint.address, !address.isEmpty else {
                return completion(ShareLinks.appStoreURL)
            }
            let body: [String: Any] = [
                "name": mint.name,
                "address": address,
                "category": mint.category.rawValue,
                "googlePlaceId": googlePlaceId,
                "location": ["type": "Point", "coordinates": [lng, lat]]
            ]
            GlobalPlaceService.shared.createOrGetGlobalPlace(placeData: body) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let venue): completion(ShareLinks.place(id: venue.place.id))
                    case .failure(let error):
                        Logger.error("Place share: couldn't make the venue for \(googlePlaceId): \(error.localizedDescription)")
                        completion(ShareLinks.appStoreURL)
                    }
                }
            }
        }
    }
}
