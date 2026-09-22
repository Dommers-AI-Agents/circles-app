import Foundation

/// Which transport failures mean "the phone can't reach us right now" — as
/// opposed to a bad request or a server fault.
///
/// A request that times out on one bar, can't resolve the host in a tunnel,
/// or is refused because roaming is off is a connectivity problem, and the
/// person should be told to check their connection rather than shown
/// "Request failed: The request timed out."
enum NetworkErrorClassifier {
    /// Whether `error`, at any depth of wrapping, is a connectivity failure.
    /// The launch pipeline hands the scene delegate whatever a service
    /// threw — `APIError.noInternet` bare, or inside `AuthError` /
    /// `UserError` / `CircleError` / `PlaceError.networkError`, or a raw
    /// `URLError` — so the alert must look through the wrappers.
    static func isConnectivityFailure(_ error: Error) -> Bool {
        switch error {
        case let api as APIError:
            if case .noInternet = api { return true }
            if case .requestFailed(let inner) = api { return isConnectivityFailure(inner) }
            return false
        case AuthError.networkError(let inner), UserError.networkError(let inner),
             CircleError.networkError(let inner), PlaceError.networkError(let inner):
            return isConnectivityFailure(inner)
        case let url as URLError:
            return isConnectivityFailure(url.code)
        default:
            let ns = error as NSError
            return ns.domain == NSURLErrorDomain && isConnectivityFailure(URLError.Code(rawValue: ns.code))
        }
    }

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
