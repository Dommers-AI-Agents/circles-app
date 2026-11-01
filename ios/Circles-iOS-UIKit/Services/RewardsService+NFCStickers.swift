import Foundation

/// One of the store's NFC stickers: its window link with a tag (`?t=`), and
/// how often it gets tapped (2026-11-01).
struct NFCSticker: Codable, Equatable {
    let tag: String
    let label: String
    /// What gets written onto the sticker
    let url: String
    let taps: Int
    let lastTapAt: String?
    let createdAt: String?
    let writtenAt: String?
    let writes: Int?
    let locked: Bool?
}

struct NFCStickerListData: Codable {
    let stickers: [NFCSticker]
    /// The untagged window link, to recognise this store's stickers
    let windowUrl: String?
}

private struct NFCStickerAck: Codable { let success: Bool }

extension RewardsService {

    func listNFCStickers(venueId: String, completion: @escaping (Result<NFCStickerListData, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/nfc-stickers", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<NFCStickerListData>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    func createNFCSticker(venueId: String, label: String, completion: @escaping (Result<NFCSticker, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/nfc-stickers", method: .post,
                                  body: ["label": label], requiresAuth: true) {
            (result: Result<RewardsEnvelope<NFCSticker>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    /// The phone wrote the sticker (and maybe locked it)
    func markNFCStickerWritten(venueId: String, tag: String, locked: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/nfc-stickers/\(tag)/written", method: .post,
                                  body: ["locked": locked], requiresAuth: true) {
            (result: Result<NFCStickerAck, APIError>) in
            completion(result.map { _ in () }.mapError { $0 as Error })
        }
    }

    func renameNFCSticker(venueId: String, tag: String, label: String, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/nfc-stickers/\(tag)", method: .patch,
                                  body: ["label": label], requiresAuth: true) {
            (result: Result<NFCStickerAck, APIError>) in
            completion(result.map { _ in () }.mapError { $0 as Error })
        }
    }

    func deleteNFCSticker(venueId: String, tag: String, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/nfc-stickers/\(tag)", method: .delete,
                                  requiresAuth: true) {
            (result: Result<NFCStickerAck, APIError>) in
            completion(result.map { _ in () }.mapError { $0 as Error })
        }
    }

    /// A customer opened a store's NFC sticker in the app: count the tap.
    /// Fire and forget; works signed out too.
    func recordStickerTap(code: String, tag: String) {
        APIService.shared.request(endpoint: "clip/sticker-tap", method: .post,
                                  body: ["code": code, "tag": tag], requiresAuth: false) {
            (_: Result<NFCStickerAck, APIError>) in
        }
    }
}
