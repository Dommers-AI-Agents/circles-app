import Foundation

/// Turns what the in-app scanner read off a QR code into a store sticker code,
/// or nil when it isn't one of ours.
///
/// Store QR codes are the same universal link the iPhone Camera app opens
/// (`https://api.favcircles.com/s/<code>`), so the link shape is decided by
/// `DeepLinkRouter` — one parser for both ways in.
enum StickerCodeExtractor {

    static func code(from payload: String, router: DeepLinkRouter = DeepLinkRouter()) -> String? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let url = URL(string: text), url.scheme != nil else { return nil }
        if case .sticker(let code)? = router.destination(for: url), !code.isEmpty {
            return code
        }
        return nil
    }
}
