import Foundation
import Testing
@testable import Circles_iOS

/// Every app notification name lives in Utilities/NotificationNames.swift, and
/// no two constants share a raw string (a shared raw string would make two
/// "different" notifications the same one).
struct NotificationNamesTests {
    private static let appRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()            // Circles-iOS-UIKitTests
        .deletingLastPathComponent()            // ios
        .appendingPathComponent("Circles-iOS-UIKit")

    private static let definition = try? String(
        contentsOf: appRoot.appendingPathComponent("Utilities/NotificationNames.swift"),
        encoding: .utf8
    )

    private static func constants() -> [(name: String, raw: String)] {
        guard let source = definition else { return [] }
        let regex = try! NSRegularExpression(pattern: #"static let (\w+) = Notification\.Name\("([^"]+)"\)"#)
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).map { match in
            (String(source[Range(match.range(at: 1), in: source)!]),
             String(source[Range(match.range(at: 2), in: source)!]))
        }
    }

    @Test func rawValuesAreUnique() throws {
        let all = Self.constants()
        try #require(all.count >= 60, "parsed only \(all.count) names from NotificationNames.swift")
        let raws = all.map(\.raw)
        let duplicates = Dictionary(grouping: raws, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        #expect(duplicates.isEmpty, "duplicate raw values: \(duplicates)")
        let names = all.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func constantsKeepTheirRawStrings() {
        #expect(Notification.Name.navigateToPlace.rawValue == "NavigateToPlace")
        #expect(Notification.Name.refreshCircles.rawValue == "RefreshCircles")
        #expect(Notification.Name.placeAddedToCircle.rawValue == "PlaceAddedToCircle")
        #expect(Notification.Name.connectionsChanged.rawValue == "ConnectionsChanged")
        #expect(Notification.Name.circleDeleted.rawValue == "circleDeleted")
        #expect(VenueOrdersViewController.ordersChanged == .venueOrdersChanged)
        #expect(MapOriginVisibility.changed == .mapOriginVisibilityChanged)
    }

    /// No inline `Notification.Name("…")` outside the definitions file.
    /// RunLiveActivity.swift is the one exception: it also compiles into the
    /// widget extension, which doesn't include NotificationNames.swift.
    @Test func noInlineLiteralsElsewhere() throws {
        let allowed: Set<String> = ["NotificationNames.swift", "RunLiveActivity.swift"]
        guard let enumerator = FileManager.default.enumerator(at: Self.appRoot, includingPropertiesForKeys: nil) else {
            Issue.record("could not read \(Self.appRoot.path)"); return
        }
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !allowed.contains(url.lastPathComponent),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if text.contains("Notification.Name(\"") { offenders.append(url.lastPathComponent) }
        }
        #expect(offenders.isEmpty, "inline notification names in: \(offenders.sorted())")
    }
}
