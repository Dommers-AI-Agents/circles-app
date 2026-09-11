import UIKit

/// The circle screen's share flow: creates a 30-day view-only share link,
/// then presents a share sheet with the circle summary text, the link as a
/// separate item (so messengers render one rich preview) and the cover
/// image when it loads. Moved verbatim from CircleDetailViewController
/// (Phase 5, circle-detail step 5); the controller keeps the bar button and
/// its `@objc` target.
final class CircleShareController {
    private weak var presenter: UIViewController?

    init(presenter: UIViewController) {
        self.presenter = presenter
    }

    /// `anchor` is resolved when the sheet actually presents (after the link
    /// and cover image arrive), as the inline code did.
    func shareCircle(_ circle: Circle, placeCount: Int, anchor: @escaping () -> UIBarButtonItem?) {
        guard let presenter = presenter else { return }
        // Show loading indicator
        let loadingAlert = UIAlertController(title: nil, message: "Creating share link...", preferredStyle: .alert)
        let loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.startAnimating()
        loadingAlert.view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loadingAlert.view.centerYAnchor, constant: 30)
        ])
        presenter.present(loadingAlert, animated: true)

        // Create share link via API
        CircleService.shared.createShareLink(
            circleId: circle.id,
            shareType: .link,
            accessLevel: .viewOnly,
            expiresIn: 30 // 30 days expiration
        ) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let share):
                        self?.presentShareSheet(with: share, circle: circle, placeCount: placeCount, anchor: anchor)
                    case .failure(let error):
                        self?.showShareError(error)
                    }
                }
            }
        }
    }

    private func presentShareSheet(with share: CircleShare, circle: Circle, placeCount: Int, anchor: @escaping () -> UIBarButtonItem?) {
        // Create formatted text to share
        var shareText = "🟦 \(circle.name)"
        if let description = circle.description {
            shareText += "\n\(description)"
        }

        let memberCount = (circle.sharedWith?.count ?? 0) + (circle.followers?.count ?? 0)
        if memberCount > 0 {
            shareText += "\n👥 \(memberCount) member\(memberCount != 1 ? "s" : "")"
        }

        shareText += "\n📍 \(placeCount) place\(placeCount != 1 ? "s" : "")"

        // Add privacy emoji
        switch circle.privacy {
        case .public:
            shareText += " 🌐"
        case .myNetwork:
            shareText += " 👥"
        case .private:
            shareText += " 🔒"
        }

        shareText += "\n\nJoin me on Circles:"

        var activityItems: [Any] = [shareText]

        // The share link is a separate item so messengers render one clean,
        // tappable rich preview (opens in-app when installed, public circle
        // page + App Store fallback otherwise) — never embed the raw URL in
        // the text
        if let shareLink = share.shareLink, let url = URL(string: shareLink) {
            activityItems.append(url)
        } else {
            activityItems.append(ShareLinks.circle(id: circle.id))
        }

        // Function to present the share sheet
        let presentShareSheet = { [weak self] in
            let activityViewController = UIActivityViewController(
                activityItems: activityItems,
                applicationActivities: nil
            )

            // For iPad
            if let popover = activityViewController.popoverPresentationController {
                popover.barButtonItem = anchor()
            }

            self?.presenter?.present(activityViewController, animated: true)
        }

        // Add cover image if available (load asynchronously)
        if let coverImageUrl = circle.coverImage,
           let url = URL(string: coverImageUrl) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                DispatchQueue.main.async {
                    if let data = data, let image = UIImage(data: data) {
                        activityItems.append(image)
                    }
                    presentShareSheet()
                }
            }.resume()
        } else {
            presentShareSheet()
        }
    }

    private func showShareError(_ error: Error) {
        let alert = UIAlertController(
            title: "Share Failed",
            message: "Unable to create share link. Please try again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter?.present(alert, animated: true)
    }
}
