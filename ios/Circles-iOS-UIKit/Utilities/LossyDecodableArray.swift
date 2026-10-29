import Foundation

/// Decodes array elements individually, dropping any that fail instead of
/// failing the entire array. One malformed record in a list response must not
/// blank a whole screen - this has bitten twice (a place with a location
/// missing its GeoJSON type broke profiles; string-format openingHours broke
/// check-in).
struct LossyDecodableArray<Element: Decodable>: Decodable {
    let elements: [Element]

    private struct AnyDecodableValue: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                decoded.append(element)
            } else {
                // Skip the malformed element and keep going
                _ = try? container.decode(AnyDecodableValue.self)
                Logger.debug("⚠️ LossyDecodableArray: dropped malformed \(Element.self) element")
            }
        }
        self.elements = decoded
    }
}
