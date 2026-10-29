import Foundation

// MARK: - Venue de-duplication
extension Place {
    /// Stable per-venue key so multiple save docs for the same real-world place
    /// collapse to one in lists: globalPlaceId → googlePlaceId → name+coords.
    var venueDedupeKey: String {
        if let g = globalPlaceId, !g.isEmpty { return "g:\(g)" }
        if let gp = googlePlaceId, !gp.isEmpty { return "gp:\(gp)" }
        let coords = location?.coordinates
        let lng = coords?.first ?? 0
        let lat = coords?.count == 2 ? coords![1] : 0
        return "n:\(name.lowercased())|\(String(format: "%.4f,%.4f", lat, lng))"
    }

    /// Collapse save docs to one representative per venue, preferring the given
    /// owner's copy and copies that have photos; preserves first-seen order.
    static func dedupedByVenue(_ places: [Place], preferredOwnerId: String) -> [Place] {
        var order: [String] = []
        var groups: [String: [Place]] = [:]
        for p in places {
            let key = p.venueDedupeKey
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(p)
        }
        let hasPhotos: (Place) -> Bool = { !($0.photos?.isEmpty ?? true) }
        return order.map { key in
            let group = groups[key] ?? []
            return group.first(where: { $0.addedBy == preferredOwnerId && hasPhotos($0) })
                ?? group.first(where: hasPhotos)
                ?? group.first(where: { $0.addedBy == preferredOwnerId })
                ?? group[0]
        }
    }
}
