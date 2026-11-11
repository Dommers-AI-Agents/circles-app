import Foundation
import MapKit

/// What an Apple Maps pick tells the server about itself (2026-11-11: Over
/// Easy in Chandler, a real restaurant, was held for approval because Apple
/// gave it no POI category and the app sent nothing else). Pure.
enum ApplePlaceIdentity {
    /// Apple's stable identifier for the place (iOS 18+), else nil
    static func identifier(of mapItem: MKMapItem?) -> String? {
        guard let mapItem else { return nil }
        if #available(iOS 18.0, *) {
            return mapItem.identifier?.rawValue
        }
        return nil
    }

    /// True when the place being saved IS the Apple result: the result has a
    /// business name and the saved name is that name (case, spacing and
    /// punctuation aside). A renamed pick, or an address entry the user
    /// named themselves, is not vouched for and waits for approval as before.
    static func vouches(mapItem: MKMapItem?, savedName: String) -> Bool {
        guard let appleName = mapItem?.name, !AppleMapItemFormFill.isResidentialAddress(name: appleName) else { return false }
        let a = normalized(appleName), b = normalized(savedName)
        return !a.isEmpty && a == b
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
