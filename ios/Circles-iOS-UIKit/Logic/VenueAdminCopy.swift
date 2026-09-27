import Foundation

/// Plain-language copy for the super-user store page: why a store's loyalty
/// program is (or isn't) live, what each counter means, and a clean address.
enum VenueAdminCopy {

    enum Tone: Equatable {
        case good, warning, neutral
    }

    struct LoyaltyLine: Equatable {
        let symbol: String
        let tone: Tone
        let title: String
        let detail: String
    }

    struct StatTile: Equatable {
        let title: String
        let value: Int
        let caption: String
        /// "+3 this month"; nil when the counter has no monthly history or
        /// nothing happened yet this month
        let monthNote: String?
    }

    // MARK: - Loyalty

    static func loyalty(
        _ loyalty: AdminVenueLoyalty,
        owner: AdminVenueAccount?,
        now: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> LoyaltyLine {
        switch loyalty.reason {
        case "comp":
            let until = parseDate(loyalty.compedUntil).map { formatDate($0, locale: locale, timeZone: timeZone) }
            var detail = until.map { "Free until \($0)." } ?? "Free with no end date."
            if let reason = humanReason(loyalty.compReason) {
                detail += " Reason: \(reason)."
            }
            detail += " Register-card points and offers work without a paid plan."
            return LoyaltyLine(symbol: "gift.fill", tone: .good, title: "Loyalty live · comped", detail: detail)

        case "owner_premium":
            if owner?.isSuperUser == true {
                return LoyaltyLine(
                    symbol: "checkmark.seal.fill", tone: .good,
                    title: "Loyalty live · admin owner",
                    detail: "The owner is a FavCircles admin, which unlocks every Business feature. It isn't a paid plan."
                )
            }
            if owner?.manuallyVerified == true {
                return LoyaltyLine(
                    symbol: "checkmark.seal.fill", tone: .good,
                    title: "Loyalty live · verified owner",
                    detail: "Business features were granted to the owner by hand, not bought in the App Store."
                )
            }
            let renews = parseDate(owner?.subscriptionExpiresAt).map { formatDate($0, locale: locale, timeZone: timeZone) }
            return LoyaltyLine(
                symbol: "checkmark.seal.fill", tone: .good,
                title: "Loyalty live · Business plan",
                detail: renews.map { "The owner's Business plan covers this store. Renews \($0)." }
                    ?? "The owner's Business plan covers this store."
            )

        case "lapsed":
            return LoyaltyLine(
                symbol: "pause.circle.fill", tone: .warning,
                title: "Loyalty paused",
                detail: "The owner's Business plan doesn't cover this store right now, so register-card scans earn no points and offers can't be redeemed. The window sticker still works."
            )

        case "no_owner":
            return LoyaltyLine(
                symbol: "person.crop.circle.badge.questionmark", tone: .neutral,
                title: "No owner yet",
                detail: "The window sticker works. Register-card points and offers need an owner on the Business plan, or a comp."
            )

        default:
            return LoyaltyLine(
                symbol: "questionmark.circle", tone: .neutral,
                title: loyalty.active ? "Loyalty live" : "Loyalty off",
                detail: ""
            )
        }
    }

    // MARK: - Stats

    static func statTiles(_ stats: AdminVenueDetailStats, thisMonth: AdminVenueMonthStats) -> [StatTile] {
        var tiles = [
            StatTile(title: "Scans", value: stats.scans, caption: "Window-sticker scans", monthNote: monthNote(thisMonth.scans)),
            StatTile(title: "Signups", value: stats.signups, caption: "New accounts from a scan", monthNote: monthNote(thisMonth.signups)),
            StatTile(title: "Sticker saves", value: stats.stickerSaves, caption: "Saved right after scanning", monthNote: monthNote(thisMonth.stickerSaves)),
            StatTile(title: "Saved by", value: stats.savers, caption: "People with it saved", monthNote: nil),
            StatTile(title: "Visits", value: stats.visits, caption: "Register-card check-ins", monthNote: monthNote(thisMonth.visits)),
            StatTile(title: "Redeemed", value: stats.redemptions, caption: "Offers cashed in", monthNote: monthNote(thisMonth.redemptions)),
            StatTile(title: "Followers", value: stats.followers, caption: "Get the store's updates", monthNote: nil)
        ]
        if stats.codeRedemptions > 0 {
            tiles.append(StatTile(title: "Codes used", value: stats.codeRedemptions, caption: "Single-use codes redeemed", monthNote: nil))
        }
        return tiles
    }

    /// "App Clip: 4 scans · 1 signup · 0 installs", or nil when the store has
    /// no App Clip traffic
    static func appClipLine(_ stats: AdminVenueDetailStats) -> String? {
        guard stats.clipScans + stats.clipSignups + stats.clipInstalls > 0 else { return nil }
        return "App Clip: \(count(stats.clipScans, "scan")) · \(count(stats.clipSignups, "signup")) · \(count(stats.clipInstalls, "install"))"
    }

    static func monthNote(_ value: Int) -> String? {
        value > 0 ? "+\(value) this month" : nil
    }

    // MARK: - Codes

    static func windowStickerExplanation() -> String {
        "For the front window. Anyone can scan it to save the store; someone new to FavCircles also gets the signup bonus. Works on the free plan."
    }

    static func registerCardExplanation(earnRate: Int?, loyaltyActive: Bool) -> String {
        let points = earnRate.map { count($0, "point") } ?? "points"
        let base = "For the counter. A customer scans it after buying something and earns \(points), once a day."
        return loyaltyActive ? base : base + " Paused until loyalty is live."
    }

    // MARK: - Text

    /// First line of a stored address, minus the "📍 0 mi from current
    /// location" suffix some older place saves carried into venue docs
    static func cleanAddress(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let line = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("📍") }
        return line?.isEmpty == false ? line : nil
    }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    static func humanReason(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Dates

    static func parseDate(_ iso: String?) -> Date? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: iso) { return date }
        return ISO8601DateFormatter().date(from: iso)
    }

    static func formatDate(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter.string(from: date)
    }
}
