import UIKit
import LinkPresentation

/// The one item a moment share hands to the share sheet: the link, dressed
/// with its title and thumbnail so the sheet's header shows the moment
/// rather than a bare URL. Messages then sends only the link, whose card
/// (title, place, badged thumbnail) comes from the share page's tags —
/// no extra text bubble.
final class MomentShareItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    let image: UIImage?

    init(url: URL, title: String, image: UIImage?) {
        self.url = url
        self.title = title
        self.image = image
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { url }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { url }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String { title }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        if let image {
            metadata.imageProvider = NSItemProvider(object: image)
            metadata.iconProvider = NSItemProvider(object: image)
        }
        return metadata
    }
}
