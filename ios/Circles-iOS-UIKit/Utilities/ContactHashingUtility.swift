import Foundation
import CryptoKit

// MARK: - Contact Hashing Utility
// Implements privacy-preserving contact matching using SHA256 hashing
// Complies with Apple Guidelines 5.1.1 by minimizing data exposure

class ContactHashingUtility {
    
    // MARK: - Singleton
    static let shared = ContactHashingUtility()
    private init() {}
    
    // MARK: - Hashing Methods
    
    /// Hash an email address for privacy-preserving matching
    /// - Parameter email: The email address to hash
    /// - Returns: SHA256 hash of the normalized email
    func hashEmail(_ email: String) -> String {
        let normalized = normalizeEmail(email)
        return sha256Hash(normalized)
    }
    
    /// Hash a phone number for privacy-preserving matching
    /// - Parameter phone: The phone number to hash
    /// - Returns: SHA256 hash of the normalized phone number
    func hashPhoneNumber(_ phone: String) -> String {
        let normalized = normalizePhoneNumber(phone)
        return sha256Hash(normalized)
    }
    
    /// Hash multiple identifiers from a contact
    /// - Parameter contact: The contact to hash
    /// - Returns: Dictionary with hashed emails and phone numbers
    func hashContact(_ contact: Contact) -> HashedContact {
        let hashedEmails = contact.emails.map { hashEmail($0) }
        let hashedPhones = contact.phoneNumbers.map { hashPhoneNumber($0) }
        
        return HashedContact(
            id: contact.id,
            name: contact.name,  // Keep name for display purposes only
            hashedEmails: hashedEmails,
            hashedPhoneNumbers: hashedPhones
        )
    }
    
    /// Hash multiple contacts
    /// - Parameter contacts: Array of contacts to hash
    /// - Returns: Array of hashed contacts
    func hashContacts(_ contacts: [Contact]) -> [HashedContact] {
        return contacts.map { hashContact($0) }
    }
    
    // MARK: - Private Methods
    
    /// Normalize email address before hashing
    /// - Converts to lowercase
    /// - Trims whitespace
    /// - Removes dots from Gmail addresses (before @)
    private func normalizeEmail(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Handle Gmail dot normalization (dots don't matter in Gmail)
        if trimmed.contains("@gmail.com") {
            let components = trimmed.split(separator: "@")
            if components.count == 2 {
                let username = String(components[0]).replacingOccurrences(of: ".", with: "")
                return "\(username)@\(components[1])"
            }
        }
        
        return trimmed
    }
    
    /// Normalize phone number before hashing
    /// - Removes all non-numeric characters
    /// - Adds country code if missing (assumes US +1)
    private func normalizePhoneNumber(_ phone: String) -> String {
        // Remove all non-numeric characters
        let cleaned = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        guard !cleaned.isEmpty else { return "" }
        
        // Handle US numbers (assume US if 10 digits without country code)
        if cleaned.count == 10 {
            return "+1\(cleaned)"
        }
        
        // Add + if missing for international numbers
        if cleaned.count > 10 && !cleaned.hasPrefix("1") {
            return "+\(cleaned)"
        }
        
        // If it starts with 1 and is 11 digits, add +
        if cleaned.count == 11 && cleaned.hasPrefix("1") {
            return "+\(cleaned)"
        }
        
        return cleaned
    }
    
    /// Generate SHA256 hash
    private func sha256Hash(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Hashed Contact Model
struct HashedContact: Codable {
    let id: String
    let name: String  // Kept for display only, not used for matching
    let hashedEmails: [String]
    let hashedPhoneNumbers: [String]
}

// MARK: - Privacy-Preserving Sync Request
struct PrivacySyncRequest: Codable {
    let hashedContacts: [HashedContact]
    let timestamp: Date
}

// MARK: - Privacy-Preserving Sync Response
struct PrivacySyncResponse: Codable {
    let matchedUserIds: [String]  // Only return user IDs, fetch full details separately
    let matchCount: Int
}

// MARK: - Extension for ContactsService Integration
extension ContactsService {
    
    /// Sync contacts using privacy-preserving hashing
    /// - Parameters:
    ///   - selectedContacts: Contacts explicitly selected by the user
    ///   - completion: Completion handler with matched users
    func privacySyncSelectedContacts(_ selectedContacts: [Contact], completion: @escaping (Result<SyncContactsResponse, Error>) -> Void) {
        // Hash the selected contacts
        let hashedContacts = ContactHashingUtility.shared.hashContacts(selectedContacts)
        
        // Prepare request body
        let hashedData = hashedContacts.map { contact in
            return [
                "name": contact.name,
                "hashedEmails": contact.hashedEmails,
                "hashedPhoneNumbers": contact.hashedPhoneNumbers
            ] as [String: Any]
        }
        
        let body: [String: Any] = [
            "hashedContacts": hashedData,
            "privacyMode": true  // Flag to indicate hashed data
        ]
        
        // Send to privacy-aware endpoint
        APIService.shared.request(
            endpoint: "users/contacts/privacy-sync",
            method: .post,
            body: body
        ) { (result: Result<SyncContactsResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}