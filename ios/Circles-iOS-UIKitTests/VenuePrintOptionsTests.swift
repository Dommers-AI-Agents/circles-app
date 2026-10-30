import Testing
@testable import Circles_iOS

struct VenuePrintOptionsTests {
    @Test func queryNamesMatchTheServer() {
        let options = VenuePrintOptions(kind: .register, format: .smallTent, qrSize: .large)
        #expect(options.queryParams == ["kind": "register", "format": "smallTent", "qr": "large"])
    }

    @Test func defaultsAreASmallTentWithAOneInchCode() {
        let options = VenuePrintOptions(kind: .window)
        #expect(options.format == .smallTent)
        #expect(options.qrSize == .small)
        #expect(options.effectiveQRInches == 1)
    }

    @Test func theCodeNeverOutgrowsTheFace() {
        let big = VenuePrintOptions(kind: .window, format: .smallTent, qrSize: .large)
        #expect(big.effectiveQRInches == 3)
        #expect(big.summary.contains("the most this layout fits"))
        let fits = VenuePrintOptions(kind: .window, format: .sign, qrSize: .large)
        #expect(fits.effectiveQRInches == 4)
        #expect(!fits.summary.contains("the most"))
    }

    @Test func fileNamesAreReadableAndSafe() {
        let options = VenuePrintOptions(kind: .window, format: .tent, qrSize: .small)
        #expect(options.fileName(storeName: "Tommy's Tavern + Tap") == "Tommys Tavern  Tap - window table tent - 1in QR.pdf")
        #expect(options.fileName(storeName: "   ") == "store - window table tent - 1in QR.pdf")
    }
}
