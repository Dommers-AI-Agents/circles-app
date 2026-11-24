import Testing
@testable import Circles_iOS

struct TotemLabelSheetTests {
    @Test func queryNamesMatchTheServer() {
        let sheet = TotemLabelSheet(venueIds: ["a", "b"], startAt: 5)
        #expect(sheet.queryParams == ["venueIds": "a,b", "startAt": "5"])
    }

    @Test func twentyLabelsToASheet() {
        #expect(TotemLabelSheet.perSheet == 20)
        #expect(TotemLabelSheet(venueIds: []).sheetCount == 0)
        #expect(TotemLabelSheet(venueIds: Array(repeating: "x", count: 20)).sheetCount == 1)
        #expect(TotemLabelSheet(venueIds: ["a"], startAt: 20).sheetCount == 1)
        #expect(TotemLabelSheet(venueIds: ["a", "b"], startAt: 20).sheetCount == 2)
        #expect(TotemLabelSheet(venueIds: Array(repeating: "x", count: 21)).sheetCount == 2)
    }

    @Test func startPositionIsOneToTwenty() {
        #expect(TotemLabelSheet.startPosition(from: " 7 ") == 7)
        #expect(TotemLabelSheet.startPosition(from: "20") == 20)
        #expect(TotemLabelSheet.startPosition(from: "0") == nil)
        #expect(TotemLabelSheet.startPosition(from: "21") == nil)
        #expect(TotemLabelSheet.startPosition(from: "x") == nil)
        #expect(TotemLabelSheet.startPosition(from: nil) == nil)
    }

    @Test func fileNameSaysTheStock() {
        #expect(TotemLabelSheet(venueIds: ["a"]).fileName == "FavCircles Totem labels - 1 store - Avery 8293.pdf")
        #expect(TotemLabelSheet(venueIds: ["a", "b"]).fileName == "FavCircles Totem labels - 2 stores - Avery 8293.pdf")
    }

    @Test func pickerLimitsFollowTheSheet() {
        #expect(StorePickPrint.windowStickers.perSheet == 24)
        #expect(StorePickPrint.totemLabels.perSheet == 20)
        #expect(StorePickPrint.totemLabels.maxStores == 100)
        #expect(StorePickPrint.totemLabels.startMessage(count: 1).contains("Avery 8293"))
    }
}
