import UIKit

/// Edit / Delete for a comment on a place, the same on the place page's
/// comment cards, the comments screen and the replies screen. The rule for
/// who sees what is `PlaceCommentActions`.
enum PlaceCommentMenu {
    /// The "more" sheet for `comment`. `onEdited` gets the saved comment;
    /// `onDelete` is the screen's own delete (it knows its rows).
    static func present(for comment: PlaceComment, on place: Place, from viewController: UIViewController, sourceView: UIView,
                        onEdited: @escaping (PlaceComment) -> Void, onDelete: @escaping () -> Void) {
        let what = comment.isReply ? "Reply" : "Comment"
        let actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = comment.allowedActions(on: place).map { action in
            switch action {
            case .edit:
                return (title: "Edit \(what)", style: .default, handler: { [weak viewController] in
                    guard let viewController else { return }
                    edit(comment, on: place, from: viewController, onEdited: onEdited)
                })
            case .delete:
                return (title: "Delete \(what)", style: .destructive, handler: onDelete)
            }
        }
        guard !actions.isEmpty else { return }
        AlertPresenter.showActionSheet(actions: actions, from: viewController, sourceView: sourceView, sourceRect: sourceView.bounds)
    }

    /// Asks for the new words and saves them
    static func edit(_ comment: PlaceComment, on place: Place, from viewController: UIViewController, onEdited: @escaping (PlaceComment) -> Void) {
        AlertPresenter.showTextInput(
            title: comment.isReply ? "Edit reply" : "Edit comment",
            initialText: comment.text,
            confirmTitle: "Save",
            from: viewController
        ) { [weak viewController] typed in
            guard let text = PlaceCommentActions.newText(from: typed, current: comment.text) else { return }
            PlaceService.shared.editPlaceComment(placeId: place.id, commentId: comment.id, text: text) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let saved):
                        onEdited(saved.keepingDetails(of: comment))
                    case .failure(let error):
                        Logger.debug("Failed to edit comment: \(error)")
                        guard let viewController else { return }
                        AlertPresenter.showError(message: "Couldn't save your changes. Please try again.", from: viewController)
                    }
                }
            }
        }
    }

    /// Confirms, then deletes `comment`; `onDeleted` runs after the server agrees
    static func confirmDelete(_ comment: PlaceComment, on place: Place, from viewController: UIViewController, onDeleted: @escaping () -> Void) {
        AlertPresenter.showConfirmation(
            title: comment.isReply ? "Delete this reply?" : "Delete this comment?",
            message: "It will be gone for everyone.",
            confirmTitle: "Delete",
            isDestructive: true,
            from: viewController,
            onConfirm: { [weak viewController] in
                PlaceService.shared.deletePlaceComment(placeId: place.id, commentId: comment.id) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            onDeleted()
                        case .failure(let error):
                            Logger.debug("Failed to delete comment: \(error)")
                            guard let viewController else { return }
                            AlertPresenter.showError(message: "Failed to delete comment. Please try again.", from: viewController)
                        }
                    }
                }
            }
        )
    }
}
