import Foundation

struct ReferralReward: Codable {
    let userId: String
    let date: String
    let type: String
    let value: Int // Number of days
    let claimed: Bool?
    let claimedDate: String?
    
    enum CodingKeys: String, CodingKey {
        case userId, date, type, value, claimed, claimedDate
    }
}