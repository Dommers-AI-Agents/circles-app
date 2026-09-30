import Testing
import Foundation
@testable import Circles_iOS

/// The place photo library's per-photo menu matches what the server allows.
struct PlacePhotoActionsTests {

    private func photo(id: String? = "p1", by: String? = "cust", isPrivate: Bool? = nil) -> AttributedPhoto {
        let json: [String: Any?] = ["id": id, "url": "https://x/\(id ?? "none").jpg", "uploadedBy": by,
                                    "uploadedAt": "2026-09-30T10:00:00Z", "source": "user_upload", "private": isPrivate]
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(AttributedPhoto.self, from: data)
    }

    @Test func ownerManagesSomeoneElsesPhoto() {
        #expect(PlacePhotoActions.actions(photo: photo(), isCover: false, viewerId: "owner", canManage: true) == [.setCover, .remove, .report])
        #expect(PlacePhotoActions.actions(photo: photo(), isCover: true, viewerId: "owner", canManage: true) == [.remove, .report])
    }

    @Test func customersDeleteTheirOwnAndReportOthers() {
        #expect(PlacePhotoActions.actions(photo: photo(), isCover: false, viewerId: "cust", canManage: false) == [.delete])
        #expect(PlacePhotoActions.actions(photo: photo(by: "other"), isCover: false, viewerId: "cust", canManage: false) == [.report])
    }

    @Test func aPrivatePhotoIsNeverOfferedAsCover() {
        #expect(!PlacePhotoActions.actions(photo: photo(by: "owner", isPrivate: true), isCover: false, viewerId: "owner", canManage: true).contains(.setCover))
    }

    @Test func legacyPhotosWithoutAnIdOfferNothing() {
        #expect(PlacePhotoActions.actions(photo: photo(id: nil), isCover: false, viewerId: "owner", canManage: true).isEmpty)
    }

    @Test func movingKeepsEveryId() {
        #expect(PlacePhotoActions.moved(["a", "b", "c", "d"], from: 3, to: 0) == ["d", "a", "b", "c"])
        #expect(PlacePhotoActions.moved(["a", "b", "c"], from: 0, to: 2) == ["b", "c", "a"])
        #expect(PlacePhotoActions.moved(["a"], from: 3, to: 0) == ["a"])
        #expect(PlacePhotoActions.reportContentId(placeId: "gp", photoId: "p1") == "gp:p1")
    }
}
