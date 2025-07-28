import Foundation

// MARK: - Shared Error Response Model
struct ErrorResponse: Codable {
    let success: Bool
    let message: String
    let errors: [String]?
    let code: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decode(String.self, forKey: .message)
        errors = try container.decodeIfPresent([String].self, forKey: .errors)
        code = try container.decodeIfPresent(String.self, forKey: .code)
    }
}

// MARK: - Account Merge Response Models
struct DuplicateAccountsResponse: Codable {
    let success: Bool
    let duplicateAccounts: [User]
}

struct MergeAccountsResponse: Codable {
    let success: Bool
    let message: String
    let primaryAccount: User
    let mergedData: MergedData
}

struct MergedData: Codable {
    let alternateEmailsAdded: [String]
    let providersLinked: [String]
    let followersAdded: Int
    let followingAdded: Int
}