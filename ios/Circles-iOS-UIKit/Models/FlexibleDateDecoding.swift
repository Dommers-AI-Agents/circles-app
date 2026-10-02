import Foundation

/// Dates arrive in more than one spelling: the server sends ISO-8601 text,
/// old endpoints a Firestore `{_seconds}` map, and our own on-disk caches
/// (JSONEncoder's default) write a number. A model that reads only one of
/// them fails to decode the others — the launch cache wrote User.createdAt
/// as a number and then couldn't read it back, so every cold start threw the
/// cache away and sat on the loading splash (2026-10-02).
enum FlexibleDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }

    /// A bare number: milliseconds or seconds since 1970, or JSONEncoder's
    /// default (seconds since 2001 — anything below 1.2e9 can't be a
    /// 1970-based date after 2008).
    static func fromNumber(_ n: Double) -> Date {
        if n > 1e11 { return Date(timeIntervalSince1970: n / 1000) }
        if n > 1.2e9 { return Date(timeIntervalSince1970: n) }
        return Date(timeIntervalSinceReferenceDate: n)
    }

    private struct FirestoreTimestamp: Decodable {
        let seconds: Double
        enum CodingKeys: String, CodingKey { case seconds = "_seconds", plainSeconds = "seconds" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let s = try c.decodeIfPresent(Double.self, forKey: .seconds) { seconds = s; return }
            seconds = try c.decode(Double.self, forKey: .plainSeconds)
        }
    }

    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Date? {
        if let text = try? container.decodeIfPresent(String.self, forKey: key) { return parse(text) }
        if let number = try? container.decodeIfPresent(Double.self, forKey: key) { return fromNumber(number) }
        if let stamp = try? container.decodeIfPresent(FirestoreTimestamp.self, forKey: key) {
            return Date(timeIntervalSince1970: stamp.seconds)
        }
        return nil
    }
}

extension KeyedDecodingContainer {
    /// Any spelling of a date (see FlexibleDate); nil, never a throw, when unreadable
    func flexibleDate(forKey key: Key) -> Date? { FlexibleDate.decode(self, key) }
}
