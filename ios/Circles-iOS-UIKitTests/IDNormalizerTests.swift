import Testing
@testable import Circles_iOS

/// One key per person: equal ids match, nothing else does.
struct IDNormalizerTests {
    @Test func equalIdsMatch() {
        #expect(IDNormalizer.isSameUser("111819744557116370195", "111819744557116370195"))
    }
    @Test func differentIdsDoNot() {
        #expect(!IDNormalizer.isSameUser("28ae89b4c9a54694b8ba24fa4d526bef", "114660021593746618908"))
        // An old dotted spelling is not treated as anyone
        #expect(!IDNormalizer.isSameUser("000454.9b5eeac93282416c9bc6dcecbc49b40f.2127", "9b5eeac93282416c9bc6dcecbc49b40f"))
    }
    @Test func missingNeverMatches() {
        #expect(!IDNormalizer.isSameUser(nil, nil))
        #expect(!IDNormalizer.isSameUser("", ""))
        #expect(!IDNormalizer.isSameUser("abc", nil))
    }
}
