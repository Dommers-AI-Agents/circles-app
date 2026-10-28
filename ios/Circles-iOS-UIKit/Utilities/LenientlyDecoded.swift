import Foundation

/// An optional field that never sinks the payload it rides in: a missing,
/// null or malformed value decodes as nil instead of throwing. For additive
/// server fields on responses a whole screen depends on (the place page's
/// store card would blank if `myOrder` ever arrived in an unexpected shape).
@propertyWrapper
struct LenientlyDecoded<Value: Codable>: Codable {
    var wrappedValue: Value?

    init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        wrappedValue = try? Value(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

extension KeyedDecodingContainer {
    /// A missing key is nil, like any optional
    func decode<Value: Codable>(_ type: LenientlyDecoded<Value>.Type, forKey key: K) throws -> LenientlyDecoded<Value> {
        try decodeIfPresent(type, forKey: key) ?? LenientlyDecoded(wrappedValue: nil)
    }
}
