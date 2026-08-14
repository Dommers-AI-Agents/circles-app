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

/// Groups places into region chips — one chip per STATE, plus one per COUNTRY
/// for non-US places.
///
/// The old chips were one-per-extracted-city, which at ZIP/typo granularity
/// produced duplicate slivers ("28269 (1)", "28269 (2)"). An adaptive
/// state/city/Elsewhere scheme was tried next and read as arbitrary — so this
/// is deliberately simple: every state with places gets a chip ("New Jersey
/// (102)", "New York (8)"). Places whose state can't be derived have no chip
/// and remain reachable under "All places".
enum RegionGrouper {

    /// Radius for the "Near me" chip. ~50 km reads as "around where I am
    /// right now" — within an outing, not within a road trip.
    static let nearMeRadiusMeters: CLLocationDistance = 50_000

    /// Countries follow the same rule as states: every country with places
    /// gets its own chip (flag + count). "Other countries" only exists as a
    /// safety net if this is ever raised above 1 again.
    static let countryChipMinPlaces = 1

    static func groups(for places: [Place], origin: CLLocation?) -> [RegionGroup] {
        var byState: [String: [Place]] = [:]     // stateCode -> places (US only)
        var stateNames: [String: String] = [:]   // stateCode -> display name
        var byCountry: [String: [Place]] = [:]   // ISO2 -> places (non-US)
        var countryNames: [String: String] = [:] // ISO2 -> display name

        for place in places {
            if let cc = place.lensCountryCode, cc != "US" {
                byCountry[cc, default: []].append(place)
                if countryNames[cc] == nil { countryNames[cc] = place.lensCountryName ?? cc }
                continue
            }
            // US (or country unknown): group by state as before.
            guard let code = place.lensStateCode else { continue }
            byState[code, default: []].append(place)
            if stateNames[code] == nil { stateNames[code] = place.lensStateName ?? code }
        }

        var result = byState.map { code, statePlaces in
            makeGroup(id: "state:\(code)", title: stateNames[code] ?? code, places: statePlaces)
        }

        // Countries dense enough get their own chip, interleaved with the
        // states by size (so a Canadian user sees Canada first, not after 40
        // states); the sparse remainder shares one "Other countries" chip.
        var sparseCountryPlaces: [Place] = []
        for (cc, countryPlaces) in byCountry {
            if countryPlaces.count >= countryChipMinPlaces {
                result.append(makeGroup(id: "country:\(cc)", title: countryNames[cc] ?? cc, places: countryPlaces))
            } else {
                sparseCountryPlaces.append(contentsOf: countryPlaces)
            }
        }

        // Most places first — the chip order then mirrors where your saving
        // actually happens, and it never reshuffles as you move around.
        var sorted = result.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.title < rhs.title : lhs.count > rhs.count
        }

        if !sparseCountryPlaces.isEmpty {
            sorted.append(makeGroup(id: "other-countries", title: "Other countries", places: sparseCountryPlaces))
        }

        // "Near me" leads when a location fix exists and something is actually
        // nearby. It sits ahead of the states because it answers the question
        // the map is usually opened with; the state order behind it never
        // changes, so the rest of the row stays where muscle memory expects.
        if let origin = origin {
            let nearby = places.filter { place in
                guard let location = place.location?.clLocation else { return false }
                return origin.distance(from: location) <= nearMeRadiusMeters
            }
            if !nearby.isEmpty {
                sorted.insert(makeGroup(id: "near-me", title: "Near me", places: nearby), at: 0)
            }
        }

        return sorted
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

    /// Country names recognized at an address tail, mapped to ISO2. Compact
    /// client-side mirror of the backend table — the server-stamped field is
    /// preferred; this only catches docs the backfill hasn't reached.
    private static let countryNamesToCode: [String: String] = [
        "united states": "US", "united states of america": "US", "usa": "US",
        "us": "US", "u.s.": "US", "u.s.a.": "US",
        "canada": "CA", "mexico": "MX",
        "united kingdom": "GB", "uk": "GB", "england": "GB", "scotland": "GB",
        "wales": "GB", "northern ireland": "GB", "great britain": "GB",
        "france": "FR", "italy": "IT", "spain": "ES", "portugal": "PT",
        "germany": "DE", "netherlands": "NL", "the netherlands": "NL",
        "belgium": "BE", "switzerland": "CH", "austria": "AT", "ireland": "IE",
        "iceland": "IS", "denmark": "DK", "norway": "NO", "sweden": "SE",
        "finland": "FI", "greece": "GR", "croatia": "HR", "czechia": "CZ",
        "czech republic": "CZ", "poland": "PL", "hungary": "HU",
        "türkiye": "TR", "turkey": "TR", "japan": "JP", "south korea": "KR",
        "china": "CN", "taiwan": "TW", "hong kong": "HK", "singapore": "SG",
        "thailand": "TH", "vietnam": "VN", "indonesia": "ID", "malaysia": "MY",
        "philippines": "PH", "india": "IN", "united arab emirates": "AE",
        "uae": "AE", "israel": "IL", "egypt": "EG", "south africa": "ZA",
        "morocco": "MA", "kenya": "KE", "australia": "AU", "new zealand": "NZ",
        "fiji": "FJ", "brazil": "BR", "argentina": "AR", "chile": "CL",
        "peru": "PE", "colombia": "CO", "ecuador": "EC", "costa rica": "CR",
        "panama": "PA", "guatemala": "GT", "belize": "BZ",
        "dominican republic": "DO", "jamaica": "JM", "bahamas": "BS",
        "the bahamas": "BS", "barbados": "BB", "cuba": "CU", "aruba": "AW",
        "curaçao": "CW", "cayman islands": "KY",
        "turks and caicos islands": "TC", "british virgin islands": "VG",
        "saint lucia": "LC", "antigua and barbuda": "AG", "bermuda": "BM"
    ]

    private static let countryDisplayNames: [String: String] = [
        "US": "United States", "CA": "Canada", "MX": "Mexico",
        "GB": "United Kingdom", "FR": "France", "IT": "Italy", "ES": "Spain",
        "PT": "Portugal", "DE": "Germany", "NL": "Netherlands",
        "BE": "Belgium", "CH": "Switzerland", "AT": "Austria", "IE": "Ireland",
        "IS": "Iceland", "DK": "Denmark", "NO": "Norway", "SE": "Sweden",
        "FI": "Finland", "GR": "Greece", "HR": "Croatia", "CZ": "Czechia",
        "PL": "Poland", "HU": "Hungary", "TR": "Türkiye", "JP": "Japan",
        "KR": "South Korea", "CN": "China", "TW": "Taiwan", "HK": "Hong Kong",
        "SG": "Singapore", "TH": "Thailand", "VN": "Vietnam",
        "ID": "Indonesia", "MY": "Malaysia", "PH": "Philippines",
        "IN": "India", "AE": "United Arab Emirates", "IL": "Israel",
        "EG": "Egypt", "ZA": "South Africa", "MA": "Morocco", "KE": "Kenya",
        "AU": "Australia", "NZ": "New Zealand", "FJ": "Fiji", "BR": "Brazil",
        "AR": "Argentina", "CL": "Chile", "PE": "Peru", "CO": "Colombia",
        "EC": "Ecuador", "CR": "Costa Rica", "PA": "Panama",
        "GT": "Guatemala", "BZ": "Belize", "DO": "Dominican Republic",
        "JM": "Jamaica", "BS": "Bahamas", "BB": "Barbados", "CU": "Cuba",
        "AW": "Aruba", "CW": "Curaçao", "KY": "Cayman Islands",
        "TC": "Turks and Caicos Islands", "VG": "British Virgin Islands",
        "LC": "Saint Lucia", "AG": "Antigua and Barbuda", "BM": "Bermuda"
    ]

    /// ISO2 country, preferring the server-derived field. Fallback order:
    /// country named at the address tail, then "has a US state" ⇒ US.
    var lensCountryCode: String? {
        if let code = countryCode, !code.isEmpty { return code }
        // Address tail (before any "📍 x mi away" hint the client appended).
        let stripped = address.components(separatedBy: "📍")[0]
        let parts = stripped
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let last = parts.last, let code = Place.countryNamesToCode[last.lowercased()] {
            return code
        }
        return lensStateCode != nil ? "US" : nil
    }

    /// Display name for the country ("Canada"), server-derived when present.
    var lensCountryName: String? {
        if let name = country, !name.isEmpty { return name }
        guard let code = lensCountryCode else { return nil }
        return Place.countryDisplayNames[code] ?? code
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

/// Fetches a single location fix for the "Near me" chip.
///
/// Never prompts — a filter chip is not worth a permission interruption, so
/// this only reads a fix the app has already earned the right to. No
/// permission (or no fix) simply means no Near me chip, which is a normal
/// state. Kept as its own retained object because a CLLocationManager that
/// goes out of scope before its callback silently never fires.
final class OneShotLocationProvider: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var completion: ((CLLocation?) -> Void)?
    private var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation(_ completion: @escaping (CLLocation?) -> Void) {
        let status = CLLocationManager.authorizationStatus()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            completion(nil)
            return
        }

        // A cached fix is plenty for a 50 km radius; skip the round trip.
        if let cached = manager.location {
            completion(cached)
            return
        }

        guard !isRunning else { return }
        isRunning = true
        self.completion = completion
        manager.requestLocation()
    }

    private func finish(_ location: CLLocation?) {
        isRunning = false
        let callback = completion
        completion = nil
        callback?(location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.debug("Near me fix unavailable: \(error.localizedDescription)")
        finish(nil)
    }
}
