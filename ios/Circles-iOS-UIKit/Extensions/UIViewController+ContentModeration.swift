import UIKit

/// The report/block sheet for content you don't own (App Review 1.2: every
/// piece of user-generated content needs a report path, and abusive users
/// must be blockable). One shared implementation so a moment, a comment, a
/// photo, and a profile all moderate identically.
extension UIViewController {

    /// Presents the "⋯" sheet for someone else's content: report it,
    /// stop following the author, or block them outright.
    func presentContentModerationSheet(
        contentType: String,
        contentId: String,
        ownerId: String,
        ownerName: String?,
        sourceView: UIView? = nil,
        onContentHidden: (() -> Void)? = nil
    ) {
        let name = (ownerName?.isEmpty == false) ? ownerName! : "this user"
        var actions: [(String, UIAlertAction.Style, () -> Void)] = []

        actions.append(("Report", .destructive, { [weak self] in
            self?.presentReportReasonSheet(
                contentType: contentType, contentId: contentId,
                ownerId: ownerId, onContentHidden: onContentHidden)
        }))

        let isFollowing = (AuthService.shared.currentUser?.following ?? []).contains(ownerId)
        if isFollowing {
            actions.append(("Stop Following \(name)", .default, { [weak self] in
                self?.moderationUnfollow(ownerId: ownerId, ownerName: name)
            }))
        }

        actions.append(("Block \(name)", .destructive, { [weak self] in
            self?.confirmAndBlock(ownerId: ownerId, ownerName: name, onBlocked: onContentHidden)
        }))

        AlertPresenter.showActionSheet(
            title: nil,
            message: nil,
            actions: actions.map { (title: $0.0, style: $0.1, handler: $0.2) },
            from: self,
            sourceView: sourceView ?? view
        )
    }

    /// Profile-level "⋯": report the person themselves (not one piece of
    /// content), stop following, or block. Used from another user's profile.
    func presentUserModerationSheet(
        userId: String,
        userName: String?,
        sourceView: UIView? = nil,
        onBlocked: (() -> Void)? = nil
    ) {
        let name = (userName?.isEmpty == false) ? userName! : "this user"
        var actions: [(String, UIAlertAction.Style, () -> Void)] = []

        actions.append(("Report \(name)", .destructive, { [weak self] in
            self?.presentUserReportReasonSheet(userId: userId, userName: name)
        }))

        let isFollowing = (AuthService.shared.currentUser?.following ?? []).contains(userId)
        if isFollowing {
            actions.append(("Stop Following \(name)", .default, { [weak self] in
                self?.moderationUnfollow(ownerId: userId, ownerName: name)
            }))
        }

        actions.append(("Block \(name)", .destructive, { [weak self] in
            self?.confirmAndBlock(ownerId: userId, ownerName: name, onBlocked: onBlocked)
        }))

        AlertPresenter.showActionSheet(
            title: nil,
            message: nil,
            actions: actions.map { (title: $0.0, style: $0.1, handler: $0.2) },
            from: self,
            sourceView: sourceView ?? view
        )
    }

    private func presentUserReportReasonSheet(userId: String, userName: String) {
        let reasons: [(label: String, code: String)] = [
            ("Inappropriate content", "inappropriate_content"),
            ("Harassment or bullying", "harassment"),
            ("Fake account or impersonation", "impersonation"),
            ("Spam", "spam"),
            ("Something else", "other")
        ]
        AlertPresenter.showActionSheet(
            title: "Report \(userName)?",
            message: "Your report is anonymous and goes straight to the FavCircles team.",
            actions: reasons.map { reason in
                (title: reason.label, style: .default, handler: { [weak self] in
                    guard let self = self else { return }
                    APIService.shared.request(
                        endpoint: "reports/user",
                        method: .post,
                        body: ["reportedUserId": userId, "reason": reason.code],
                        requiresAuth: true
                    ) { [weak self] (result: Result<ReportSubmitResponse, APIError>) in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let response):
                                self?.showSuccess(response.message ?? "Report submitted. Thank you for keeping FavCircles safe.")
                            case .failure(let error):
                                self?.showError(error.serverMessage ?? "Couldn't submit the report. Please try again.")
                            }
                        }
                    }
                })
            },
            from: self,
            sourceView: view
        )
    }

    private func presentReportReasonSheet(
        contentType: String,
        contentId: String,
        ownerId: String,
        onContentHidden: (() -> Void)?
    ) {
        let reasons: [(label: String, code: String)] = [
            ("Sexual content", "sexual_content"),
            ("Violence or dangerous acts", "violence"),
            ("Hate or harassment", "hate_harassment"),
            ("Spam or misleading", "spam"),
            ("Something else", "other")
        ]
        AlertPresenter.showActionSheet(
            title: "Why are you reporting this?",
            message: "Your report is anonymous. Content reported by multiple people is hidden automatically pending review.",
            actions: reasons.map { reason in
                (title: reason.label, style: .default, handler: { [weak self] in
                    self?.submitContentReport(
                        contentType: contentType, contentId: contentId,
                        ownerId: ownerId, reason: reason.code,
                        onContentHidden: onContentHidden)
                })
            },
            from: self,
            sourceView: view
        )
    }

    private func submitContentReport(
        contentType: String,
        contentId: String,
        ownerId: String,
        reason: String,
        onContentHidden: (() -> Void)?
    ) {
        APIService.shared.request(
            endpoint: "reports/content",
            method: .post,
            body: [
                "contentId": contentId,
                "contentType": contentType,
                "contentOwnerId": ownerId,
                "reason": reason
            ],
            requiresAuth: true
        ) { [weak self] (result: Result<ReportSubmitResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    self.showSuccess(response.message ?? "Report submitted. Thank you for keeping FavCircles safe.")
                    if response.autoHidden == true { onContentHidden?() }
                case .failure(let error):
                    self.showError(error.serverMessage ?? "Couldn't submit the report. Please try again.")
                }
            }
        }
    }

    private func moderationUnfollow(ownerId: String, ownerName: String) {
        APIService.shared.request(
            endpoint: "users/\(ownerId)/unfollow",
            method: .post,
            body: [:],
            requiresAuth: true
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.showSuccess("You no longer follow \(ownerName).")
                case .failure(let error):
                    self?.showError(error.serverMessage ?? "Couldn't unfollow. Please try again.")
                }
            }
        }
    }

    private func confirmAndBlock(ownerId: String, ownerName: String, onBlocked: (() -> Void)?) {
        AlertPresenter.showConfirmation(
            title: "Block \(ownerName)?",
            message: "You won't see each other's places, moments, comments, or profiles anywhere in FavCircles, and any follows or connections between you are removed. You can unblock later from Settings.",
            confirmTitle: "Block",
            from: self
        ) { [weak self] in
            BlockService.shared.blockUser(userId: ownerId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.showSuccess("\(ownerName) has been blocked.")
                        onBlocked?()
                    case .failure(let error):
                        self?.showError((error as? APIError)?.serverMessage ?? "Couldn't block. Please try again.")
                    }
                }
            }
        }
    }
}

struct ReportSubmitResponse: Decodable {
    let success: Bool
    let message: String?
    let autoHidden: Bool?
}
