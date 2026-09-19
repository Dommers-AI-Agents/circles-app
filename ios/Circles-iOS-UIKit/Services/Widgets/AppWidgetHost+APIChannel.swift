import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore
import StripeApplePay
import PassKit

/// The authenticated widgets/ API channel.
extension AppWidgetHost {
    // MARK: - Widget API channel

    /// Authenticated raw call for widget-owned endpoints. Only `widgets/`
    /// paths are allowed; the widget package never sees the token.
    func request(_ request: WidgetAPIRequest) async throws -> Data {
        guard request.path.hasPrefix("widgets/"), !request.path.contains("..") else {
            throw WidgetAPIError(status: 403, message: "Path not allowed")
        }
        guard let token = KeychainService.shared.getAuthToken(), !token.isEmpty else {
            throw WidgetAPIError(status: 401, message: "Sign in to continue")
        }
        guard let url = URL(string: "\(APIEnvironment.current.baseURL)/\(request.path)") else {
            throw WidgetAPIError(status: 400, message: "Bad request")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (body?["message"] as? String) ?? (body?["error"] as? String) ?? "Request failed (\(status))"
            throw WidgetAPIError(status: status, code: body?["code"] as? String, message: message)
        }
        return data
    }

}
