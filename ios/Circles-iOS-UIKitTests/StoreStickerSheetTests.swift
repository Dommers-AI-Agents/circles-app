import Testing
@testable import Circles_iOS

struct StoreStickerSheetTests {
    @Test func queryNamesMatchTheServer() {
        let sheet = StoreStickerSheet(venueIds: ["a", "b"], startAt: 5)
        #expect(sheet.queryParams == ["venueIds": "a,b", "kind": "window", "startAt": "5"])
    }

    @Test func sheetsCountFromTheStartPosition() {
        #expect(StoreStickerSheet(venueIds: []).sheetCount == 0)
        #expect(StoreStickerSheet(venueIds: Array(repeating: "x", count: 24)).sheetCount == 1)
        #expect(StoreStickerSheet(venueIds: ["a", "b"], startAt: 23).sheetCount == 1)
        #expect(StoreStickerSheet(venueIds: ["a", "b", "c"], startAt: 23).sheetCount == 2)
        #expect(StoreStickerSheet(venueIds: Array(repeating: "x", count: 25)).sheetCount == 2)
    }

    @Test func startPositionIsOneToTwentyFour() {
        #expect(StoreStickerSheet.startPosition(from: " 7 ") == 7)
        #expect(StoreStickerSheet.startPosition(from: "24") == 24)
        #expect(StoreStickerSheet.startPosition(from: "0") == nil)
        #expect(StoreStickerSheet.startPosition(from: "25") == nil)
        #expect(StoreStickerSheet.startPosition(from: "abc") == nil)
        #expect(StoreStickerSheet.startPosition(from: nil) == nil)
    }

    @Test func picksKeepTheirOrder() {
        var ids = StoreStickerSheet.toggled([], "a")
        ids = StoreStickerSheet.toggled(ids, "c")
        ids = StoreStickerSheet.toggled(ids, "b")
        #expect(ids == ["a", "c", "b"])
        #expect(StoreStickerSheet.toggled(ids, "c") == ["a", "b"])
    }

    @Test func fileNameSaysHowMany() {
        #expect(StoreStickerSheet(venueIds: ["a"]).fileName == "FavCircles stickers - 1 store - Avery 22805.pdf")
        #expect(StoreStickerSheet(venueIds: ["a", "b"]).fileName == "FavCircles stickers - 2 stores - Avery 22805.pdf")
    }
}
