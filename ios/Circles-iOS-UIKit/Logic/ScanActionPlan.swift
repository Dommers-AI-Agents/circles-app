import Foundation

/// What the app does with a scanned Scan Action QR (2026-11-11), decided
/// from the server's answer. Pure and tested; ScanActionCoordinator
/// performs it.
enum ScanActionPlan: Equatable {
    /// One place or a set: show the cards, let them pick (all ticked except
    /// ones they already have), pick a circle, save
    case review(places: [ScanAction.Place], preselected: Set<String>)
    /// They already have every place: open it (one) or say so (several)
    case alreadyHaveAll(places: [ScanAction.Place])
    /// The QR ran out; `from` is who to ask for a new one
    case expired(from: String?)
    /// Every place in it has since gone (held for approval, removed)
    case nothingLeft
    /// A "show me how" guide over the real screens
    case guide(ScreenGuideKind)
    /// A store owner's QR with no store named: find the business, claim it
    case claimStore
    /// A store QR made for one store: confirm, then it's theirs
    case redeemStore(name: String)
    /// They already redeemed it: Manage Store with its walkthrough
    case manageStore(venueId: String)
    /// Someone else already used this store's QR
    case storeTaken(name: String?)
    /// A kind this build doesn't know: update the app
    case updateApp

    static func plan(for action: ScanAction) -> ScanActionPlan {
        switch action.kind {
        case .place, .placeSet:
            if action.expired { return .expired(from: action.creator?.displayName) }
            guard !action.places.isEmpty else { return .nothingLeft }
            let fresh = action.places.filter { $0.alreadySaved != true }
            if fresh.isEmpty { return .alreadyHaveAll(places: action.places) }
            return .review(places: action.places, preselected: Set(fresh.map(\.globalPlaceId)))
        case .guide:
            guard let raw = action.guide?.appGuide, let kind = ScreenGuideKind(rawValue: raw), kind.isScannable else {
                return .updateApp
            }
            return .guide(kind)
        case .storeSetup:
            guard let store = action.store else { return .claimStore }
            if store.redeemedByViewer == true {
                return store.venueId.map(ScanActionPlan.manageStore) ?? .claimStore
            }
            if store.redeemed == true { return .storeTaken(name: store.name) }
            if action.expired { return .expired(from: nil) }
            return .redeemStore(name: store.name ?? "your store")
        case .unknown:
            return .updateApp
        }
    }
}

extension ScreenGuideKind {
    /// The guides a "show me how" QR can open (backend/config/scanGuides.js)
    var isScannable: Bool {
        switch self {
        case .sharePlace, .makeCircle, .addPlace, .checkIn, .widgets, .rewards, .storeSetup: return true
        case .findPeople, .profile, .ownPlace, .storeManage: return false
        }
    }
}

/// The words after a save, the creator side's notices. Pure.
enum ScanActionCopy {
    static func saved(_ result: ScanActionSaveResult, circleName: String?) -> (title: String, message: String) {
        let into = circleName.map { " to \($0)" } ?? ""
        let savedCount = result.saved.count
        var lines: [String] = []
        if result.alreadySaved.count == 1, let name = result.alreadySaved.first?.name {
            lines.append("You already had \(name)\(result.alreadySaved.first?.circleName.map { " in \($0)" } ?? "").")
        } else if result.alreadySaved.count > 1 {
            lines.append("You already had \(result.alreadySaved.count) of them.")
        }
        if !result.failed.isEmpty {
            lines.append(result.failed.contains { $0.upgradeRequired == true }
                ? "Your plan is full, so \(result.failed.count == 1 ? "1 place wasn't" : "\(result.failed.count) places weren't") saved."
                : "\(result.failed.count == 1 ? "1 place" : "\(result.failed.count) places") couldn't be saved.")
        }
        let title: String
        switch savedCount {
        case 0: title = result.alreadySaved.isEmpty ? "Nothing saved" : "Already on your map"
        case 1: title = "Saved \(result.saved[0].name ?? "it")\(into)"
        default: title = "Saved \(savedCount) places\(into)"
        }
        return (title, lines.joined(separator: " "))
    }

    /// The creator's line under the QR: what got left out and why
    static func leftOut(privateCount: Int, hiddenCount: Int) -> String? {
        var parts: [String] = []
        if privateCount > 0 { parts.append(privateCount == 1 ? "1 private place left out" : "\(privateCount) private places left out") }
        if hiddenCount > 0 { parts.append(hiddenCount == 1 ? "1 place that can't be shared yet left out" : "\(hiddenCount) places that can't be shared yet left out") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A Home or circle list cut to fit a QR, said out loud (never trimmed silently)
    static func capped(total: Int, max: Int) -> String? {
        total > max ? "The first \(max) of \(total) places go in the QR." : nil
    }

    static func setTitle(circleName: String?, category: String?, tag: String?) -> String {
        let base = circleName ?? "My places"
        if let tag, !tag.isEmpty { return "\(base): \(tag)" }
        if let category, !category.isEmpty { return "\(base): \(category)" }
        return base
    }
}
