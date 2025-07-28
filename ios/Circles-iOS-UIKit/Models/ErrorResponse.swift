import Foundation

// MARK: - Shared Error Response Model
struct ErrorResponse: Codable {
    let success: Bool
    let message: String
    let errors: [String]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decode(String.self, forKey: .message)
        errors = try container.decodeIfPresent([String].self, forKey: .errors)
    }
}