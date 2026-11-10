import UIKit

/// Hands an image to Instagram: a story through its pasteboard scheme, or
/// any post through the system share sheet (Instagram's extension appears
/// when it's installed). Needs `instagram-stories` and `instagram` in
/// LSApplicationQueriesSchemes and the Meta app id from Info.plist.
enum InstagramShare {

    private static var appId: String? {
        Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String
    }

    private static var storiesURL: URL? {
        guard let appId else { return nil }
        return URL(string: "instagram-stories://share?source_application=\(appId)")
    }

    static var storiesAvailable: Bool {
        guard let url = storiesURL else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// False when Instagram isn't there to take it
    @discardableResult
    static func shareToStory(_ image: UIImage) -> Bool {
        guard storiesAvailable, let url = storiesURL, let png = image.pngData() else { return false }
        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": png]],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )
        UIApplication.shared.open(url)
        return true
    }

    static func sharePost(_ image: UIImage, from presenter: UIViewController, sourceView: UIView? = nil) {
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView ?? presenter.view
            popover.sourceRect = sourceView?.bounds ?? CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        }
        presenter.present(sheet, animated: true)
    }
}
