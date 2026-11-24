import Testing
@testable import Circles_iOS

struct RoundLabelSheetTests {
    private func totem(_ ids: [String], startAt: Int = 1) -> RoundLabelSheet {
        RoundLabelSheet(design: .totem, venueIds: ids, startAt: startAt)
    }

    @Test func queryNamesMatchTheServer() {
        #expect(totem(["a", "b"], startAt: 5).queryParams == ["venueIds": "a,b", "startAt": "5"])
        #expect(RoundLabelSheet(design: .table, venueIds: ["a"], startAt: 2).queryParams == ["venueIds": "a", "startAt": "2", "copies": "1"])
    }

    @Test func eachDesignHasItsOwnEndpoint() {
        #expect(RoundLabelSheet.Design.totem.endpoint == "rewards/stickers/totem")
        #expect(RoundLabelSheet.Design.table.endpoint == "rewards/stickers/table")
    }

    @Test func twentyLabelsToASheet() {
        #expect(RoundLabelSheet.perSheet == 20)
        #expect(totem([]).sheetCount == 0)
        #expect(totem(Array(repeating: "x", count: 20)).sheetCount == 1)
        #expect(totem(["a"], startAt: 20).sheetCount == 1)
        #expect(totem(["a", "b"], startAt: 20).sheetCount == 2)
        #expect(totem(Array(repeating: "x", count: 21)).sheetCount == 2)
    }

    @Test func tableStickersComeSeveralToAStore() {
        let twelve = RoundLabelSheet(design: .table, venueIds: ["a", "b"], startAt: 1, copies: 12)
        #expect(twelve.queryParams["copies"] == "12")
        #expect(twelve.labelCount == 24)
        #expect(twelve.sheetCount == 2)
        #expect(twelve.fileName == "FavCircles table stickers - 2 stores, 12 each - Avery 8293.pdf")
        #expect(RoundLabelSheet(design: .table, venueIds: ["a"], startAt: 1, copies: 20).sheetCount == 1)
        // A Totem has one base: copies never reach its print
        let totemSheet = RoundLabelSheet(design: .totem, venueIds: ["a"], startAt: 1, copies: 5)
        #expect(totemSheet.queryParams["copies"] == nil)
        #expect(totemSheet.labelCount == 1)
        #expect(totemSheet.fileName == "FavCircles Totem labels - 1 store - Avery 8293.pdf")
    }

    @Test func copiesAreOneToAHundredAndFourHundredInAll() {
        #expect(RoundLabelSheet.copies(from: " 12 ", stores: 1) == 12)
        #expect(RoundLabelSheet.copies(from: "100", stores: 4) == 100)
        #expect(RoundLabelSheet.copies(from: "100", stores: 5) == nil)
        #expect(RoundLabelSheet.copies(from: "80", stores: 5) == 80)
        #expect(RoundLabelSheet.copies(from: "0", stores: 1) == nil)
        #expect(RoundLabelSheet.copies(from: "101", stores: 1) == nil)
        #expect(RoundLabelSheet.copies(from: "x", stores: 1) == nil)
        #expect(RoundLabelSheet.copies(from: nil, stores: 1) == nil)
        #expect(RoundLabelSheet.maxCopies(stores: 1) == 100)
        #expect(RoundLabelSheet.maxCopies(stores: 5) == 80)
        #expect(RoundLabelSheet.maxCopies(stores: 100) == 4)
        #expect(StorePickPrint.copiesMessage(count: 1).contains("this store"))
        #expect(StorePickPrint.copiesMessage(count: 5).contains("each of the 5 stores"))
        #expect(StorePickPrint.copiesMessage(count: 5).contains("up to 80"))
        #expect(StorePickPrint.tableStickers.startMessage(count: 1, copies: 12).contains("12 round stickers, all for one store"))
        #expect(StorePickPrint.tableStickers.startMessage(count: 2, copies: 12).contains("24 round stickers, 12 for each of 2 stores"))
    }

    @Test func startPositionIsOneToTwenty() {
        #expect(RoundLabelSheet.startPosition(from: " 7 ") == 7)
        #expect(RoundLabelSheet.startPosition(from: "20") == 20)
        #expect(RoundLabelSheet.startPosition(from: "0") == nil)
        #expect(RoundLabelSheet.startPosition(from: "21") == nil)
        #expect(RoundLabelSheet.startPosition(from: "x") == nil)
        #expect(RoundLabelSheet.startPosition(from: nil) == nil)
    }

    @Test func fileNameSaysWhatAndTheStock() {
        #expect(totem(["a"]).fileName == "FavCircles Totem labels - 1 store - Avery 8293.pdf")
        #expect(totem(["a", "b"]).fileName == "FavCircles Totem labels - 2 stores - Avery 8293.pdf")
        #expect(RoundLabelSheet(design: .table, venueIds: ["a", "b"]).fileName == "FavCircles table stickers - 2 stores - Avery 8293.pdf")
    }

    @Test func pickerLimitsFollowTheSheet() {
        #expect(StorePickPrint.windowStickers.perSheet == 24)
        #expect(StorePickPrint.windowStickers.roundDesign == nil)
        for pick in [StorePickPrint.totemLabels, .tableStickers] {
            #expect(pick.perSheet == 20)
            #expect(pick.maxStores == 100)
            #expect(pick.startMessage(count: 1).contains("Avery 8293"))
        }
        #expect(StorePickPrint.totemLabels.roundDesign == .totem)
        #expect(StorePickPrint.tableStickers.roundDesign == .table)
        #expect(StorePickPrint.totemLabels.startTitle == "Start at label #")
        #expect(StorePickPrint.tableStickers.startTitle == "Start at sticker #")
        #expect(StorePickPrint.tableStickers.startMessage(count: 2).contains("2 round stickers"))
    }
}
