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

    /// The launch alert gets the error however the service wrapped it.
    @Test func seesThroughServiceWrappers() {
        #expect(NetworkErrorClassifier.isConnectivityFailure(APIError.noInternet))
        #expect(NetworkErrorClassifier.isConnectivityFailure(AuthError.networkError(APIError.noInternet)))
        #expect(NetworkErrorClassifier.isConnectivityFailure(CircleError.networkError(URLError(.timedOut))))
        #expect(NetworkErrorClassifier.isConnectivityFailure(APIError.requestFailed(URLError(.cannotFindHost))))
        #expect(NetworkErrorClassifier.isConnectivityFailure(NSError(domain: NSURLErrorDomain, code: URLError.notConnectedToInternet.rawValue)))
        #expect(!NetworkErrorClassifier.isConnectivityFailure(APIError.unauthorized))
        #expect(!NetworkErrorClassifier.isConnectivityFailure(NSError(domain: "PreloadManager", code: -1)))
    }

    @Test(arguments: [URLError.Code.badURL, .cancelled, .badServerResponse,
                      .userAuthenticationRequired, .fileDoesNotExist])
    func everythingElseIsNot(code: URLError.Code) {
        #expect(!NetworkErrorClassifier.isConnectivityFailure(code))
    }
}
