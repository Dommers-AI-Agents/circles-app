import Foundation

/// Widgets pinned to the Home button's long-press menu (Wes, 2026-10-08:
/// jump straight to a widget from anywhere). Order is the order pinned;
/// a few at most so the menu stays a glance.
struct HomeButtonPin: Codable, Equatable {
    let id: String
    let title: String
}

enum HomeButtonPins {
    static let limit = 6

    static func isPinned(_ id: String, in pins: [HomeButtonPin]) -> Bool { pins.contains { $0.id == id } }

    /// Pins or unpins `pin`. Pinning past the limit drops the oldest.
    static func toggle(_ pin: HomeButtonPin, in pins: [HomeButtonPin]) -> [HomeButtonPin] {
        if isPinned(pin.id, in: pins) { return pins.filter { $0.id != pin.id } }
        return Array((pins + [pin]).suffix(limit))
    }

    /// Pins whose widget still exists (a widget can be retired from the package)
    static func valid(_ pins: [HomeButtonPin], knownIds: Set<String>) -> [HomeButtonPin] {
        pins.filter { knownIds.contains($0.id) }
    }
}

/// This phone's pins, per signed-in account.
enum HomeButtonPinStore {
    private static var key: String { "homeButtonWidgetPins.\(AuthService.shared.getUserId() ?? "anon")" }

    static func load() -> [HomeButtonPin] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let pins = try? JSONDecoder().decode([HomeButtonPin].self, from: data) else { return [] }
        return pins
    }

    static func save(_ pins: [HomeButtonPin]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(pins), forKey: key)
    }
}
