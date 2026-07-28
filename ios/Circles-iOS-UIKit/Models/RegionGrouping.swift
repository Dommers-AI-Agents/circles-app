import Foundation
import CoreLocation

/// A region filter chip in the profile Places lens: a set of places that share
/// a geography, sized to be worth filtering by.
struct RegionGroup {
    let id: String            // stable: "state:NC", "city:charlotte|NC", "state-more:NJ", "elsewhere"
    let title: String         // "North Carolina", "Charlotte", "New Jersey · more", "Elsewhere"
    let count: Int
    let placeIds: Set<String>
    let centroid: CLLocationCoordinate2D?

    func contains(_ place: Place) -> Bool { placeIds.contains(place.id) }
}

/// Groups places into region chips — one chip per STATE.
///
/// The old chips were one-per-extracted-city, which at ZIP/typo granularity
/// produced duplicate slivers ("28269 (1)", "28269 (2)"). An adaptive
/// state/city/Elsewhere scheme was tried next and read as arbitrary — so this
/// is deliberately simple: every state with places gets a chip ("New Jersey
/// (102)", "New York (8)"). Places whose state can't be derived have no chip
/// and remain reachable under "All places".
enum RegionGrouper {

    static func groups(for places: [Place], origin: CLLocation?) -> [RegionGroup] {
        var byState: [String: [Place]] = [:]   // stateCode -> places
        var stateNames: [String: String] = [:] // stateCode -> display name

        for place in places {
            guard let code = place.lensStateCode else { continue }
            byState[code, default: []].append(place)
            if stateNames[code] == nil { stateNames[code] = place.lensStateName ?? code }
        }

        let result = byState.map { code, statePlaces in
            makeGroup(id: "state:\(code)", title: stateNames[code] ?? code, places: statePlaces)
        }

        // Nearest state first when we know where the user is; otherwise the
        // busiest.
        return result.sorted { lhs, rhs in
            if let origin = origin, let l = lhs.centroid, let r = rhs.centroid {
                let ld = origin.distance(from: CLLocation(latitude: l.latitude, longitude: l.longitude))
                let rd = origin.distance(from: CLLocation(latitude: r.latitude, longitude: r.longitude))
                if ld != rd { return ld < rd }
            }
            return lhs.count == rhs.count ? lhs.title < rhs.title : lhs.count > rhs.count
        }
    }

    private static func makeGroup(id: String, title: String, places: [Place]) -> RegionGroup {
        var latSum = 0.0, lonSum = 0.0, n = 0.0
        for place in places {
            guard let coordinate = place.location?.clLocation?.coordinate else { continue }
            latSum += coordinate.latitude
            lonSum += coordinate.longitude
            n += 1
        }
        return RegionGroup(
            id: id,
            title: title,
            count: places.count,
            placeIds: Set(places.map { $0.id }),
            centroid: n > 0 ? CLLocationCoordinate2D(latitude: latSum / n, longitude: lonSum / n) : nil
        )
    }
}

// MARK: - Location fields with address fallback

extension Place {

    private static let usStateCodes: Set<String> = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA",
        "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT",
        "VA","WA","WV","WI","WY","DC","PR","VI","GU"
    ]

    /// Address components with the country suffix and bare ZIP components
    /// dropped — the two things that used to masquerade as "cities".
    private var cleanedAddressComponents: [String] {
        var parts = address
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        while let last = parts.last,
              ["united states", "united states of america", "usa", "us", "u.s.", "u.s.a."].contains(last.lowercased())
                || last.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) != nil {
            parts.removeLast()
        }
        return parts
    }

    /// Two-letter state, preferring the server-derived field.
    var lensStateCode: String? {
        if let code = stateCode, !code.isEmpty { return code }
        // Fallback: scan cleaned components from the end for "NC" / "NC 28269".
        for part in cleanedAddressComponents.reversed() {
            let tokens = part.components(separatedBy: " ").filter { !$0.isEmpty }
            for token in tokens.reversed() where token.count == 2 && Place.usStateCodes.contains(token.uppercased()) {
                return token.uppercased()
            }
        }
        return nil
    }

    /// Display name for the state ("North Carolina"), server-derived when present.
    var lensStateName: String? {
        if let name = state, !name.isEmpty { return name }
        return lensStateCode
    }

    /// City, preferring the server-derived field; falls back to the component
    /// before the state in the cleaned address. Never a ZIP, never a country.
    var lensCity: String? {
        if let city = city, !city.isEmpty { return city }
        let parts = cleanedAddressComponents
        guard parts.count >= 2 else { return nil }
        // Find the component carrying the state; the city precedes it.
        for (index, part) in parts.enumerated().reversed() {
            let tokens = part.components(separatedBy: " ").filter { !$0.isEmpty }
            let hasState = tokens.contains { $0.count == 2 && Place.usStateCodes.contains($0.uppercased()) }
            if hasState {
                if tokens.count > 1, let first = tokens.first,
                   !Place.usStateCodes.contains(first.uppercased()) {
                    // "Charlotte NC" style: city glued to the state token.
                    return tokens.dropLast().joined(separator: " ")
                }
                return index > 0 ? parts[index - 1] : nil
            }
        }
        // No state anywhere: second-to-last cleaned component, if non-numeric.
        let candidate = parts[parts.count - 2]
        return candidate.rangeOfCharacter(from: .decimalDigits) == nil ? candidate : nil
    }
}
