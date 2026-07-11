import UIKit
import AuthenticationServices

/// Drives the Swarm (Foursquare) OAuth import: fetches the authorization URL
/// from the backend, runs the OAuth dance in ASWebAuthenticationSession,
/// then pulls the user's saved lists (and optionally check-ins) as a
/// normalized payload and hands it to the shared prepare/review flow.
final class SwarmImportCoordinator: NSObject {

    static let shared = SwarmImportCoordinator()
    private override init() {}

    /// The `circles://` scheme registered in Info.plist; the backend
    /// callback redirects to circles://import/swarm?status=…
    private let callbackScheme = "circles"

    private var authSession: ASWebAuthenticationSession?
    private weak var presentingViewController: ImportSourceSelectionViewController?

    // MARK: - API response models

    private struct SwarmAuthUrlResponse: Decodable {
        let success: Bool
        let url: String
    }

    private struct SwarmFetchResponse: Decodable {
        let success: Bool
        let payload: SwarmPayload
    }

    private struct SwarmPayload: Decodable {
        let source: String
        let lists: [SwarmList]
        let checkinsTruncated: Bool?
    }

    private struct SwarmList: Decodable {
        let name: String
        let places: [SwarmPlace]
    }

    private struct SwarmPlace: Decodable {
        let name: String
        let address: String?
        let lat: Double?
        let lng: Double?
        let category: String?
        let notes: String?
        let tags: [String]?
        let sourceExternalId: String?
        let sourceUrl: String?

        var asCandidate: ImportPlaceCandidate {
            ImportPlaceCandidate(
                name: name,
                address: address,
                lat: lat,
                lng: lng,
                category: category,
                notes: notes,
                tags: tags ?? [],
                sourceExternalId: sourceExternalId,
                sourceUrl: sourceUrl
            )
        }
    }

    // MARK: - Flow

    func start(from viewController: ImportSourceSelectionViewController) {
        presentingViewController = viewController

        APIService.shared.request(
            endpoint: "import/swarm/auth-url",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<SwarmAuthUrlResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.beginAuthSession(urlString: response.url)
                case .failure(let error):
                    self?.presentingViewController?.showError(error.localizedDescription)
                }
            }
        }
    }

    private func beginAuthSession(urlString: String) {
        guard let url = URL(string: urlString) else {
            presentingViewController?.showError("Invalid Swarm authorization URL.")
            return
        }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if error != nil {
                    // User cancelled the sheet — no error alert needed
                    return
                }
                let status = callbackURL.flatMap {
                    URLComponents(url: $0, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "status" })?.value
                }
                guard status == "ok" else {
                    self.presentingViewController?.showError("Swarm authorization was not completed.")
                    return
                }
                self.askAboutCheckins()
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    private func askAboutCheckins() {
        guard let viewController = presentingViewController else { return }
        AlertPresenter.showActionSheet(
            title: "Swarm Connected",
            message: "What would you like to import?",
            actions: [
                (title: "Saved lists only", style: .default, handler: { [weak self] in
                    self?.fetchSwarmData(includeCheckins: false)
                }),
                (title: "Saved lists + check-in history", style: .default, handler: { [weak self] in
                    self?.fetchSwarmData(includeCheckins: true)
                })
            ],
            from: viewController
        )
    }

    private func fetchSwarmData(includeCheckins: Bool) {
        guard let viewController = presentingViewController else { return }
        let loadingAlert = AlertPresenter.showLoading(
            message: "Fetching your places from Swarm…",
            from: viewController
        )

        APIService.shared.request(
            endpoint: "import/swarm/fetch",
            method: .post,
            body: ["includeCheckins": includeCheckins],
            requiresAuth: true
        ) { (result: Result<SwarmFetchResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) { [weak self] in
                    guard let self = self, let viewController = self.presentingViewController else { return }
                    switch result {
                    case .success(let response):
                        let lists = response.payload.lists.map {
                            ImportList(name: $0.name, places: $0.places.map { $0.asCandidate })
                        }
                        guard !lists.isEmpty else {
                            viewController.showError("No saved places found in your Swarm account.")
                            return
                        }
                        viewController.prepareAndReview(source: .swarm, lists: lists)
                    case .failure(let error):
                        viewController.showError(error.localizedDescription)
                    }
                }
            }
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SwarmImportCoordinator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentingViewController?.view.window ?? ASPresentationAnchor()
    }
}
