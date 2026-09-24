import Testing
@testable import Circles_iOS

struct CareScaleInputTests {
    @Test func plainNumbersAndForgivingShapes() {
        #expect(CareScaleInput.value(from: "7") == 7)
        #expect(CareScaleInput.value(from: " 8 ") == 8)
        #expect(CareScaleInput.value(from: "7/10") == 7)
        #expect(CareScaleInput.value(from: "10.") == 10)
        #expect(CareScaleInput.value(from: "0") == 0)
    }

    @Test func outOfRangeAndWordsAreNil() {
        #expect(CareScaleInput.value(from: "11") == nil)
        #expect(CareScaleInput.value(from: "seven") == nil)
        #expect(CareScaleInput.value(from: "") == nil)
        #expect(CareScaleInput.value(from: "-3") == nil)
    }
}
