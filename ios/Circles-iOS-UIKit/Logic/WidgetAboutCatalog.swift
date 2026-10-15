import Foundation

/// What a widget does, for the "i" on its page. The words come from
/// `Resources/WidgetAbout.json`, which website/tools/build-widgets-page.js
/// writes from the same list as favcircles.com/widgets.html.
struct WidgetAbout: Decodable, Equatable {
    let name: String
    let tagline: String
    let features: [String]
}

enum WidgetAboutCatalog {
    static func decode(_ data: Data) -> [String: WidgetAbout] {
        (try? JSONDecoder().decode([String: WidgetAbout].self, from: data)) ?? [:]
    }

    /// The page's copy, or the widget's own one-liners when the list has no
    /// row for it yet.
    static func about(id: String, in catalog: [String: WidgetAbout],
                      fallbackName: String, fallbackTagline: String, fallbackDetail: String?) -> WidgetAbout {
        if let about = catalog[id] { return about }
        let detail = fallbackDetail.flatMap { $0 == fallbackTagline ? nil : $0 }
        return WidgetAbout(name: fallbackName, tagline: fallbackTagline, features: detail.map { [$0] } ?? [])
    }

    static let bundled: [String: WidgetAbout] = {
        guard let url = Bundle.main.url(forResource: "WidgetAbout", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return decode(data)
    }()
}
