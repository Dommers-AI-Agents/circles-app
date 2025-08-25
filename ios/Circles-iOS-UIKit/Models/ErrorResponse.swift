import Foundation

// MARK: - Shared Error Response Model
struct ErrorResponse: Codable {
    let success: Bool
    let message: String
    private let errorsDict: [String: [String]]?  // New format: field-specific errors
    private let errorsArray: [String]?  // Old format: array of errors
    let code: String?
    
    // Computed property to get errors as dictionary
    var fieldErrors: [String: [String]]? {
        if let dict = errorsDict {
            return dict
        } else if let array = errorsArray {
            return ["general": array]
        }
        return nil
    }
    
    private enum CodingKeys: String, CodingKey {
        case success, message, errors, code
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decode(String.self, forKey: .message)
        
        // Try to decode as dictionary first (new format), fall back to array (old format)
        if let fieldErrors = try? container.decode([String: [String]].self, forKey: .errors) {
            errorsDict = fieldErrors
            errorsArray = nil
        } else if let arrayErrors = try? container.decode([String].self, forKey: .errors) {
            errorsArray = arrayErrors
            errorsDict = nil
        } else {
            errorsDict = nil
            errorsArray = nil
        }
        
        code = try container.decodeIfPresent(String.self, forKey: .code)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(message, forKey: .message)
        
        // Encode errors based on which one is present
        if let dict = errorsDict {
            try container.encode(dict, forKey: .errors)
        } else if let array = errorsArray {
            try container.encode(array, forKey: .errors)
        }
        
        try container.encodeIfPresent(code, forKey: .code)
    }
    
    // Helper to get all error messages as a single string
    var allErrorMessages: String {
        guard let fieldErrors = fieldErrors else { return message }
        
        var messages: [String] = []
        for (field, errors) in fieldErrors {
            if field == "general" {
                messages.append(contentsOf: errors)
            } else {
                for error in errors {
                    messages.append("\(field.capitalized): \(error)")
                }
            }
        }
        
        return messages.isEmpty ? message : messages.joined(separator: "\n")
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