import AuthenticationServices
import UIKit

// Minimal Sign in with Apple wrapper — modeled on the completion handling in
// SocialAuthService.authorizationController(controller:didCompleteWithAuthorization:)
// but with zero app coupling. AuthenticationServices is a system framework,
// so this costs the clip nothing in binary size.
final class ClipAppleSignIn: NSObject {

    struct Credential {
        let idToken: String
        let displayName: String?
        let email: String?
    }

    private var completion: ((Result<Credential, Error>) -> Void)?
    private weak var presentationWindow: UIWindow?

    func signIn(from window: UIWindow?, completion: @escaping (Result<Credential, Error>) -> Void) {
        self.completion = completion
        self.presentationWindow = window

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
}

extension ClipAppleSignIn: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            completion?(.failure(ClipAPIError.server("Apple sign-in didn't return a valid token. Please try again.")))
            completion = nil
            return
        }

        // Name/email are only present on the very first Apple authorization
        var displayName: String?
        if let nameComponents = credential.fullName {
            let formatted = PersonNameComponentsFormatter().string(from: nameComponents)
            displayName = formatted.isEmpty ? nil : formatted
        }

        completion?(.success(Credential(idToken: idToken,
                                        displayName: displayName,
                                        email: credential.email)))
        completion = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        // User cancellation isn't an error worth surfacing
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            completion = nil
            return
        }
        completion?(.failure(error))
        completion = nil
    }
}

extension ClipAppleSignIn: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return presentationWindow ?? ASPresentationAnchor()
    }
}
