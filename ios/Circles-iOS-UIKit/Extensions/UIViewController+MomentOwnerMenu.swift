import UIKit

/// Owner-only actions for a Moment shown from the video overlay's "..." button.
/// Shared by both reel hosts (home Moments tab + the full-screen VideoReelsViewController)
/// so the Delete / Change-Privacy flow lives in one place.
extension UIViewController {

    /// Presents the owner menu for a moment: Change Privacy + Delete.
    /// - onPrivacyChanged: the host updates its local model to the new visibility.
    /// - onDeleted: the host removes the moment from its list / collection view.
    func presentMomentOwnerMenu(for reel: PlaceVideo,
                                sourceView: UIView? = nil,
                                onPrivacyChanged: @escaping (VideoVisibility) -> Void,
                                onDeleted: @escaping () -> Void) {
        AlertPresenter.showActionSheet(
            title: "Moment options",
            message: "Privacy: \(reel.visibility.displayLabel)",
            actions: [
                ("Change Privacy", .default, { [weak self] in
                    self?.presentMomentPrivacyPicker(for: reel, onPrivacyChanged: onPrivacyChanged)
                }),
                ("Delete", .destructive, { [weak self] in
                    self?.confirmDeleteMoment(reel, onDeleted: onDeleted)
                })
            ],
            from: self,
            sourceView: sourceView
        )
    }

    private func presentMomentPrivacyPicker(for reel: PlaceVideo,
                                            onPrivacyChanged: @escaping (VideoVisibility) -> Void) {
        let actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] =
            VideoVisibility.allCases.map { level in
                let mark = level == reel.visibility ? "  ✓" : ""
                return ("\(level.displayLabel) — \(level.pickerSubtitle)\(mark)", .default, { [weak self] in
                    guard let self = self, level != reel.visibility else { return }
                    let loading = AlertPresenter.showLoading(message: "Updating…", from: self)
                    APIService.shared.updateVideoVisibility(videoId: reel.id, visibility: level) { result in
                        DispatchQueue.main.async {
                            loading.dismiss(animated: true) {
                                switch result {
                                case .success:
                                    onPrivacyChanged(level)
                                    self.showSuccess("Privacy updated to \(level.displayLabel)")
                                case .failure(let error):
                                    self.showError(error)
                                }
                            }
                        }
                    }
                })
            }
        AlertPresenter.showActionSheet(title: "Who can see this moment?", message: nil,
                                       actions: actions, from: self)
    }

    private func confirmDeleteMoment(_ reel: PlaceVideo, onDeleted: @escaping () -> Void) {
        showConfirmation(
            title: "Delete moment?",
            message: "This can't be undone.",
            confirmTitle: "Delete",
            isDestructive: true
        ) { [weak self] in
            guard let self = self else { return }
            let loading = AlertPresenter.showLoading(message: "Deleting…", from: self)
            APIService.shared.deleteVideo(videoId: reel.id) { result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        switch result {
                        case .success:
                            onDeleted()
                            NotificationCenter.default.post(
                                name: Notification.Name("MomentDeleted"),
                                object: nil,
                                userInfo: ["videoId": reel.id])
                            self.showSuccess("Moment deleted")
                        case .failure(let error):
                            self.showError(error)
                        }
                    }
                }
            }
        }
    }
}
