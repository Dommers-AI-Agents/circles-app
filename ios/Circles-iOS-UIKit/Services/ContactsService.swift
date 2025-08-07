import Foundation
import Contacts
import UIKit

// MARK: - Contact Models
struct Contact: Codable {
    let id: String
    let name: String
    let emails: [String]
    let phoneNumbers: [String]
    let profileImage: Data?
}

struct SyncContactsRequest: Codable {
    let contacts: [Contact]
}

struct SyncContactsResponse: Codable {
    let success: Bool
    let matchedUsers: [User]
    let totalContacts: Int
    let matchedCount: Int
}

struct InviteContactsRequest: Codable {
    struct Invite: Codable {
        let type: String // "email" or "sms"
        let email: String?
        let phoneNumber: String?
        let contactName: String?
    }
    
    let invites: [Invite]
}

struct InviteContactsResponse: Codable {
    struct Results: Codable {
        struct SentInvite: Codable {
            let type: String
            let recipient: String
            let message: String?
            let clientSend: Bool?
        }
        
        struct FailedInvite: Codable {
            let recipient: String
            let error: String
        }
        
        let sent: [SentInvite]
        let failed: [FailedInvite]
    }
    
    let success: Bool
    let results: Results
    let sentCount: Int
    let failedCount: Int
}

struct SuggestedUsersResponse: Codable {
    let success: Bool
    let suggestedUsers: [User]
    let count: Int
}

// MARK: - Contacts Service
class ContactsService {
    static let shared = ContactsService()
    
    private let contactStore = CNContactStore()
    private let apiService = APIService.shared
    
    private init() {}
    
    // MARK: - Permission Management
    
    func checkContactsPermission() -> CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }
    
    func requestContactsPermission(completion: @escaping (Bool) -> Void) {
        contactStore.requestAccess(for: .contacts) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    Logger.error("Failed to request contacts permission: \(error)")
                }
                completion(granted)
            }
        }
    }
    
    // MARK: - Fetching Contacts
    
    func fetchContacts(completion: @escaping (Result<[Contact], Error>) -> Void) {
        let authStatus = checkContactsPermission()
        guard authStatus == .authorized else {
            completion(.failure(NSError(domain: "ContactsService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Contacts permission not granted"
            ])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let keysToFetch: [CNKeyDescriptor] = [
                    CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor,
                    CNContactEmailAddressesKey as CNKeyDescriptor,
                    CNContactPhoneNumbersKey as CNKeyDescriptor,
                    CNContactImageDataKey as CNKeyDescriptor,
                    CNContactIdentifierKey as CNKeyDescriptor
                ]
                
                let request = CNContactFetchRequest(keysToFetch: keysToFetch)
                var contacts: [Contact] = []
                
                try self?.contactStore.enumerateContacts(with: request) { cnContact, _ in
                    let name = "\(cnContact.givenName) \(cnContact.familyName)".trimmingCharacters(in: .whitespaces)
                    
                    // Skip contacts without a name
                    guard !name.isEmpty else { return }
                    
                    let emails = cnContact.emailAddresses.map { $0.value as String }
                    let phoneNumbers = cnContact.phoneNumbers.map { $0.value.stringValue }
                    
                    // Only include contacts with at least one email or phone number
                    guard !emails.isEmpty || !phoneNumbers.isEmpty else { return }
                    
                    let contact = Contact(
                        id: cnContact.identifier,
                        name: name,
                        emails: emails,
                        phoneNumbers: phoneNumbers,
                        profileImage: cnContact.imageData
                    )
                    
                    contacts.append(contact)
                }
                
                DispatchQueue.main.async {
                    Logger.info("Fetched \(contacts.count) contacts")
                    completion(.success(contacts))
                }
                
            } catch {
                DispatchQueue.main.async {
                    Logger.error("Failed to fetch contacts: \(error)")
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Syncing with Backend
    
    func syncContactsWithBackend(completion: @escaping (Result<SyncContactsResponse, Error>) -> Void) {
        fetchContacts { [weak self] result in
            switch result {
            case .success(let contacts):
                self?.sendContactsToBackend(contacts, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func sendContactsToBackend(_ contacts: [Contact], completion: @escaping (Result<SyncContactsResponse, Error>) -> Void) {
        let contactsToSync = contacts.map { contact in
            return [
                "name": contact.name,
                "emails": contact.emails,
                "phoneNumbers": contact.phoneNumbers
            ] as [String: Any]
        }
        
        let body: [String: Any] = ["contacts": contactsToSync]
        
        apiService.request(
            endpoint: "users/contacts/sync-contacts",
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
    
    // MARK: - Suggested Users
    
    func fetchSuggestedUsers(limit: Int = 10, completion: @escaping (Result<[User], Error>) -> Void) {
        apiService.request(
            endpoint: "users/contacts/suggested?limit=\(limit)",
            method: .get
        ) { (result: Result<SuggestedUsersResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.suggestedUsers))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Invitations
    
    func inviteContacts(_ invites: [InviteContactsRequest.Invite], completion: @escaping (Result<InviteContactsResponse, Error>) -> Void) {
        let invitesArray = invites.map { invite in
            var inviteDict: [String: Any] = ["type": invite.type]
            if let email = invite.email {
                inviteDict["email"] = email
            }
            if let phoneNumber = invite.phoneNumber {
                inviteDict["phoneNumber"] = phoneNumber
            }
            if let contactName = invite.contactName {
                inviteDict["contactName"] = contactName
            }
            return inviteDict
        }
        
        let body: [String: Any] = ["invites": invitesArray]
        
        apiService.request(
            endpoint: "users/contacts/invite-contacts",
            method: .post,
            body: body
        ) { (result: Result<InviteContactsResponse, APIError>) in
            switch result {
            case .success(let response):
                // Handle SMS invites that need to be sent from the client
                for invite in response.results.sent {
                    if invite.type == "sms", let message = invite.message, invite.clientSend == true {
                        self.sendSMSInvite(to: invite.recipient, message: message)
                    }
                }
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - SMS Handling
    
    private func sendSMSInvite(to phoneNumber: String, message: String) {
        guard let url = URL(string: "sms:\(phoneNumber)&body=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            Logger.error("Failed to create SMS URL")
            return
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Bulk Operations
    
    func followMultipleUsers(_ userIds: [String], completion: @escaping (Result<[String: Bool], Error>) -> Void) {
        var results: [String: Bool] = [:]
        let group = DispatchGroup()
        
        for userId in userIds {
            group.enter()
            
            // Make direct API call to follow user
            apiService.request(
                endpoint: "users/\(userId)/follow",
                method: .post,
                body: [:]
            ) { (result: Result<SimpleAPIResponse, APIError>) in
                switch result {
                case .success:
                    results[userId] = true
                case .failure:
                    results[userId] = false
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(.success(results))
        }
    }
    
    func sendMultipleConnectionRequests(_ userIds: [String], completion: @escaping (Result<[String: Bool], Error>) -> Void) {
        var results: [String: Bool] = [:]
        let group = DispatchGroup()
        
        for userId in userIds {
            group.enter()
            NetworkManager.shared.sendConnectionRequest(to: userId) { result in
                switch result {
                case .success:
                    results[userId] = true
                case .failure:
                    results[userId] = false
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(.success(results))
        }
    }
}