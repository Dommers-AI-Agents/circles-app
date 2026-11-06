import UIKit
import SafariServices

/// Opens the admin dashboard already signed in: the server hands this
/// signed-in admin a one-time code (60 s, single use) that the page trades
/// for its own short session. No password changes hands. Used by Settings and
/// by admin alerts' taps (2026-11-06: those went nowhere).
enum AdminDashboardOpener {
    static func open(from presenter: UIViewController) {
        let loading = AlertPresenter.showLoading(message: "Opening dashboard…", from: presenter)
        APIService.shared.request(
            endpoint: "admin/dashboard/handoff",
            method: .post,
            body: [:],
            requiresAuth: true
        ) { [weak presenter] (result: Result<AdminHandoffResponse, APIError>) in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let presenter else { return }
                    switch result {
                    case .success(let response):
                        guard let url = URL(string: response.url) else { return }
                        let safari = SFSafariViewController(url: url)
                        safari.preferredControlTintColor = Constants.Colors.primary
                        presenter.present(safari, animated: true)
                    case .failure(let error):
                        AlertPresenter.showError(error, from: presenter)
                    }
                }
            }
        }
    }
}

/// POST /admin/dashboard/handoff
private struct AdminHandoffResponse: Decodable {
    let url: String
}
