import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore
import StripeApplePay
import PassKit

/// Image uploads: the compressing path and the print-resolution path.
extension AppWidgetHost {
    // MARK: - Media

    /// Same pipeline as place/profile photos (compresses, returns a public URL).
    func uploadImage(_ jpeg: Data) async throws -> URL {
        let urlString: String = try await withCheckedThrowingContinuation { continuation in
            PlaceService.shared.uploadImage(jpeg) { continuation.resume(with: $0) }
        }
        guard let url = URL(string: urlString) else { throw WidgetAPIError(status: 500, message: "Bad upload URL") }
        return url
    }

    /// Print artwork goes to its own endpoint, never through `uploadImage`.
    /// That path targets 750KB and downsizes to 1280px on its second attempt,
    /// which would quietly turn a 300 DPI card into a blurry one.
    func uploadPrintImage(_ jpeg: Data) async throws -> URL {
        let payload: [String: String] = [
            "image": jpeg.base64EncodedString(),
            "filename": "postcard-print.jpg"
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request(WidgetAPIRequest(.post, "widgets/postcard/mail/upload", body: body))
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let urlString = json?["imageUrl"] as? String, let url = URL(string: urlString) else {
            throw WidgetAPIError(status: 500, message: "Bad upload URL")
        }
        return url
    }

}
