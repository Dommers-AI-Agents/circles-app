import UIKit

/// Owner-only actions for a Moment shown from the video overlay's "..." button.
/// Shared by both reel hosts (home Moments tab + the full-screen VideoReelsViewController)
/// so the Delete / Change-Privacy flow lives in one place.
extension UIViewController {

    /// Presents the owner menu for a moment: Change Privacy + Delete.
    /// - onPrivacyChanged: the host updates its local model to the new
    ///   visibility and named Inner Circle list (nil unless Inner Circle).
    /// - onDeleted: the host removes the moment from its list / collection view.
    func presentMomentOwnerMenu(for reel: PlaceVideo,
                                sourceView: UIView? = nil,
                                onPrivacyChanged: @escaping (VideoVisibility, String?) -> Void,
                                onDeleted: @escaping () -> Void) {
        AlertPresenter.showActionSheet(
            title: "Moment options",
            message: "Privacy: \(Self.momentPrivacyLabel(for: reel))",
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

    /// Menu for a viewer who is TAGGED in someone else's moment:
    /// "Remove me from this Moment" (self-service untag — the consent story),
    /// plus a path into the normal moderation sheet.
    func presentMomentTaggedViewerMenu(for reel: PlaceVideo,
                                       sourceView: UIView? = nil,
                                       onUntagged: @escaping () -> Void,
                                       onMoreOptions: @escaping () -> Void) {
        AlertPresenter.showActionSheet(
            title: "Moment options",
            message: "You're tagged in this Moment",
            actions: [
                ("Remove me from this Moment", .destructive, { [weak self] in
                    guard let self = self else { return }
                    let loading = AlertPresenter.showLoading(message: "Removing tag…", from: self)
                    APIService.shared.request(
                        endpoint: "videos/\(reel.id)/tags/me",
                        method: .delete,
                        requiresAuth: true
                    ) { (result: Result<UntagResponse, APIError>) in
                        DispatchQueue.main.async {
                            loading.dismiss(animated: true) {
                                switch result {
                                case .success:
                                    onUntagged()
                                case .failure(let error):
                                    AlertPresenter.showError(error, from: self)
                                }
                            }
                        }
                    }
                }),
                ("More options…", .default, { onMoreOptions() })
            ],
            from: self,
            sourceView: sourceView
        )
    }

    /// "Family" for a moment limited to that list, else the tier's label.
    private static func momentPrivacyLabel(for reel: PlaceVideo) -> String {
        if reel.visibility == .innerCircle, let listId = reel.audienceListId,
           let list = InnerCircleManager.shared.usableLists.first(where: { $0.id == listId }) {
            return list.name
        }
        return reel.visibility.displayLabel
    }

    /// One row per tier, and one per named Inner Circle list — the same
    /// audiences the moment composer's picker offers.
    private func presentMomentPrivacyPicker(for reel: PlaceVideo,
                                            onPrivacyChanged: @escaping (VideoVisibility, String?) -> Void) {
        InnerCircleManager.shared.primeIfNeeded { [weak self] in
            DispatchQueue.main.async {
                self?.showMomentPrivacySheet(for: reel, onPrivacyChanged: onPrivacyChanged)
            }
        }
    }

    private func showMomentPrivacySheet(for reel: PlaceVideo,
                                        onPrivacyChanged: @escaping (VideoVisibility, String?) -> Void) {
        let choices = MomentAudienceChoices.choices(lists: InnerCircleManager.shared.usableLists,
                                                    current: reel.visibility,
                                                    currentListId: reel.audienceListId)
        let actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] =
            choices.map { choice in
                let mark = choice.isSelected ? "  ✓" : ""
                return ("\(choice.title) — \(choice.subtitle)\(mark)", .default, { [weak self] in
                    guard let self = self, !choice.isSelected else { return }
                    let loading = AlertPresenter.showLoading(message: "Updating…", from: self)
                    APIService.shared.updateMomentAudience(videoId: reel.id,
                                                           visibility: choice.visibility,
                                                           audienceListId: choice.listId) { result in
                        DispatchQueue.main.async {
                            loading.dismiss(animated: true) {
                                switch result {
                                case .success:
                                    onPrivacyChanged(choice.visibility, choice.listId)
                                    self.showSuccess("Privacy updated to \(choice.title)")
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


extension APIService {
    /// Change a moment's audience: its tier plus, for Inner Circle, which named
    /// list. PUT /videos/:id (owner-checked); the server clears the list for
    /// any other tier, and NSNull clears it when "anyone on my lists" is picked.
    func updateMomentAudience(videoId: String, visibility: VideoVisibility, audienceListId: String?,
                              completion: @escaping (Result<Void, APIError>) -> Void) {
        request(
            endpoint: "videos/\(videoId)",
            method: .put,
            body: ["visibility": visibility.rawValue, "audienceListId": audienceListId ?? NSNull()],
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            completion(result.map { _ in () })
        }
    }
}

struct UntagResponse: Decodable {
    struct Payload: Decodable { let removed: Bool }
    let success: Bool
    let data: Payload
}
