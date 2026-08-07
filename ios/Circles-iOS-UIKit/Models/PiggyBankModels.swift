import Foundation

// FavCoin piggy bank models (/api/piggy-bank). Separate from the store-loyalty
// rewards system — parallel tabs in the '$' section.

/// Materialized balance for the current user.
struct PiggyBank: Decodable {
    let pendingCoins: Int
    let confirmedCoins: Int
    let lifetimeCoins: Int
    let settledOnChain: Int
    let walletAddress: String?   // linked self-custody Cactus address (Phase 4)
}

/// An in-flight claim (confirmed coins on their way to the user's wallet).
struct PiggyActiveClaim: Decodable {
    let id: String
    let status: String       // claim_pending | claim_sending | claim_sent | settled | claim_failed
    let coins: Int
    let feeCoins: Int?
    let netCoins: Int?
    let catAmount: Int?
    let address: String
    let txId: String?
    let createdAt: String
}

/// One append-only ledger row.
struct PiggyLedgerEvent: Decodable {
    let id: String
    let eventType: String
    let coins: Int
    let status: String        // earn: pending|confirmed|reversed|held · claim: claim_*|settled
    let createdAt: String
    let clearAt: String?
    let txId: String?         // claim rows: on-chain transaction id once sent
    let explorerUrl: String?  // settled claims: deep link to the created coin

    var isPending: Bool { status == "pending" }
    var isReversed: Bool { status == "reversed" }

    var isClaim: Bool { eventType == "claim" }
    var isClaimInFlight: Bool {
        ["claim_pending", "claim_sending", "claim_sent"].contains(status)
    }
    var isSettled: Bool { status == "settled" }
    var isClaimFailed: Bool { status == "claim_failed" }

    /// "Added a place", "Friend saved your place", ...
    var displayTitle: String {
        switch eventType {
        case "add_place": return "Added a place"
        case "create_circle": return "Created a circle"
        case "share_circle": return "Shared a circle"
        case "connection_accepted": return "New connection"
        case "referral_signup": return "Referred a friend"
        case "place_adopted": return "Friend saved your place"
        case "suggestion_posted": return "Posted a suggestion"
        case "check_in": return "Checked in"
        case "place_photo": return "Added a place photo"
        case "moment_posted": return "Posted a Moment"
        case "profile_completed": return "Completed your profile"
        case "place_liked": return "Liked a place"
        case "place_comment": return "Commented on a place"
        case "user_followed": return "Followed someone"
        case "claim": return "Sent to your wallet"
        default: return eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var createdDate: Date? {
        ISO8601DateFormatter.piggyFlexible.dateFlexible(from: createdAt)
    }
}

/// Display config the backend ships so the client never hardcodes the economy.
struct PiggyBankConfigPayload: Decodable {
    let coinValues: [String: Int]
    let clearingWindowHours: Int?
    let minConfirmedToClaim: Int?
    let claimFeeCoins: Int?
    let claimsEnabled: Bool?     // false/absent → claim UI stays "coming soon"
    let explorerBaseUrl: String?
}

struct PiggyBankResponse: Decodable {
    let success: Bool
    let bank: PiggyBank
    let activeClaim: PiggyActiveClaim?
    let events: [PiggyLedgerEvent]
    let config: PiggyBankConfigPayload
}

struct PiggyLinkWalletResponse: Decodable {
    let success: Bool
    let walletAddress: String
}

struct PiggyClaimResponse: Decodable {
    let success: Bool
    let claim: PiggyActiveClaim
}

struct PiggyBankHistoryResponse: Decodable {
    let success: Bool
    let events: [PiggyLedgerEvent]
}

/// The credit stub riding on the create-place response — drives the deposit
/// animation. Optional everywhere: an old server or a failed credit must
/// never break place creation.
struct PiggyBankCredit: Decodable {
    let credited: Bool
    let coins: Int?
}

extension ISO8601DateFormatter {
    static let piggyFlexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Backend ISO strings vary in fractional seconds — try both.
    func dateFlexible(from string: String) -> Date? {
        if let d = date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

/// FavCoin follows the Bitcoin convention: the currency's name is singular
/// ("FavCoin is a crypto coin"), while a count of units takes the plural
/// ("+5 FavCoins"). One place decides, so "1 FavCoins" can't slip into the UI.
enum PiggyBankFormatting {
    static func coinUnit(_ count: Int) -> String {
        count == 1 ? "FavCoin" : "FavCoins"
    }

    /// "1 FavCoin" / "12 FavCoins"
    static func coins(_ count: Int) -> String {
        "\(count) \(coinUnit(count))"
    }
}
