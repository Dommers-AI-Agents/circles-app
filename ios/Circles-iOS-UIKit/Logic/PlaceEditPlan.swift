import Foundation
import CoreLocation

/// What saving Edit Place sends where.
///
/// A place's shared details (name, address/location, category, description,
/// phone, website) belong to the place record and change only through
/// PlaceDetailsService — for the store's owner/managers and admins. Personal
/// fields (notes, privacy, tags, circle) go to the person's own save. Only
/// what actually changed is sent, so an unchanged field never overwrites a
/// newer value someone else set.
enum PlaceEditPlan {
    struct Details: Equatable {
        var name: String?
        var address: String?
        var category: String?
        var description: String?
        var phone: String?
        var website: String?
        var coordinate: CLLocationCoordinate2D?

        static func == (lhs: Details, rhs: Details) -> Bool {
            lhs.name == rhs.name && lhs.address == rhs.address && lhs.category == rhs.category
                && lhs.description == rhs.description && lhs.phone == rhs.phone && lhs.website == rhs.website
                && PlaceEditPlan.sameSpot(lhs.coordinate, rhs.coordinate)
        }
    }

    /// The request body for the shared-details change: changed fields only,
    /// trimmed; a cleared optional field is sent as "" (the server clears it).
    /// Empty when nothing changed.
    static func detailChanges(original: Details, edited: Details) -> [String: Any] {
        var body: [String: Any] = [:]
        func compare(_ key: String, _ old: String?, _ new: String?) {
            let before = clean(old), after = clean(new)
            if before != after { body[key] = after ?? "" }
        }
        compare("name", original.name, edited.name)
        compare("address", original.address, edited.address)
        compare("category", original.category, edited.category)
        compare("description", original.description, edited.description)
        compare("phone", original.phone, edited.phone)
        compare("website", original.website, edited.website)
        if let moved = edited.coordinate, !sameSpot(original.coordinate, moved) {
            body["location"] = ["type": "Point", "coordinates": [moved.longitude, moved.latitude]]
        }
        // A name can't be cleared
        if let name = body["name"] as? String, name.isEmpty { body.removeValue(forKey: "name") }
        return body
    }

    static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Within about a metre: the same pin.
    static func sameSpot(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a.latitude - b.latitude) < 0.00001 && abs(a.longitude - b.longitude) < 0.00001
        default: return false
        }
    }
}
