import Foundation
import Testing
@testable import Circles_iOS

struct NetworkErrorClassifierTests {
    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut,
                      .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                      .dataNotAllowed, .internationalRoamingOff])
    func weakOrNoSignalIsConnectivity(code: URLError.Code) {
        #expect(NetworkErrorClassifier.isConnectivityFailure(code))
    }

    @Test(arguments: [URLError.Code.badURL, .cancelled, .badServerResponse,
                      .userAuthenticationRequired, .fileDoesNotExist])
    func everythingElseIsNot(code: URLError.Code) {
        #expect(!NetworkErrorClassifier.isConnectivityFailure(code))
    }
}
