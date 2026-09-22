import Foundation

/// Which transport failures mean "the phone can't reach us right now" — as
/// opposed to a bad request or a server fault.
///
/// A request that times out on one bar, can't resolve the host in a tunnel,
/// or is refused because roaming is off is a connectivity problem, and the
/// person should be told to check their connection rather than shown
/// "Request failed: The request timed out."
enum NetworkErrorClassifier {
    static func isConnectivityFailure(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .dataNotAllowed,
             .internationalRoamingOff,
             .callIsActive:
            return true
        default:
            return false
        }
    }
}
