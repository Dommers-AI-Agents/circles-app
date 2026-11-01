import PassKit
import UIKit

/// "Add to Apple Wallet" for a store's rewards card (2026-11-01): the server
/// signs a card with the customer's points there, Wallet shows it near the
/// store and refreshes it after every scan or redemption.
enum WalletCardPresenter {

    /// Wallet exists on this device (iPhone; not every iPad)
    static var isAvailable: Bool { PKAddPassesViewController.canAddPasses() }

    /// Apple's own button, sized for a card row
    static func makeButton(action: @escaping () -> Void) -> UIView {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    static func present(venueId: String, from presenter: UIViewController) {
        guard isAvailable else {
            return AlertPresenter.showInfo(title: "Apple Wallet isn't available",
                                           message: "This device can't hold Wallet cards.", from: presenter)
        }
        let loading = AlertPresenter.showLoading(message: "Making your card\u{2026}", from: presenter)
        RewardsService.shared.downloadWalletCard(venueId: venueId) { result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    switch result {
                    case .success(let data):
                        guard let pass = try? PKPass(data: data),
                              let addVC = PKAddPassesViewController(pass: pass) else {
                            return AlertPresenter.showError(message: "Couldn't open the Wallet card. Try again in a moment.", from: presenter)
                        }
                        presenter.present(addVC, animated: true)
                    case .failure(let error):
                        AlertPresenter.showError(error, from: presenter)
                    }
                }
            }
        }
    }
}

extension RewardsService {
    /// The signed .pkpass for this store's card
    func downloadWalletCard(venueId: String, completion: @escaping (Result<Data, Error>) -> Void) {
        APIService.shared.requestData(endpoint: "rewards/venues/\(venueId)/wallet-pass") { result in
            completion(result.mapError { $0 as Error })
        }
    }
}
