import Foundation

/// Illustrated avatars for people who'd rather not upload a photo (Wes,
/// 2026-11-17: "an option to pick a male or female avatar"). Each one is a
/// real image at favcircles.com/avatars/<id>.png, stored on the profile like
/// any photo URL, so emails, the website and store screens show it too. The
/// app bundles the same files (asset "avatar-<id>") and never downloads them.
/// Art: DiceBear "Avataaars" and "Bottts" by Pablo Stanley, free for
/// commercial use; rebuilt by website/tools/avatars/gen.js. Pure.
enum ProfileAvatarCatalog {

    static let baseURL = "https://favcircles.com/avatars/"

    struct Group: Equatable {
        let title: String
        let ids: [String]
    }

    static let groups: [Group] = [
        Group(title: "Women", ids: (1...6).map { "woman-\($0)" }),
        Group(title: "Men", ids: (1...6).map { "man-\($0)" }),
        Group(title: "Robots", ids: (1...3).map { "robot-\($0)" })
    ]

    static var allIds: [String] { groups.flatMap(\.ids) }

    static func url(for id: String) -> String { "\(baseURL)\(id).png" }

    /// The catalog id a stored profile picture points at, or nil when it's
    /// anything else (a photo, a stock emoji avatar, an unknown file).
    static func id(from urlString: String?) -> String? {
        guard let value = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix(baseURL), value.hasSuffix(".png") else { return nil }
        let id = String(value.dropFirst(baseURL.count).dropLast(".png".count))
        return allIds.contains(id) ? id : nil
    }

    /// The bundled asset's name for an id.
    static func assetName(for id: String) -> String { "avatar-\(id)" }
}
