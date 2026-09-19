import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore
import StripeApplePay
import PassKit

/// Apple Pay: whether the device can pay, and presenting the wallet.
extension AppWidgetHost {
    // MARK: - Payment

    /// Apple Pay only, and this asks whether the DEVICE can pay — not whether
    /// a card is already in Wallet.
    ///
    /// It used to ask `StripeAPI.deviceSupportsApplePay()`, which returns false
    /// when Wallet is empty. That hid the paid postcard option outright on any
    /// device with no card set up, which is every fresh device — including the
    /// iPad App Review tested 1.3.3 on, so the review found no Apple Pay
    /// anywhere in the app and rejected it under Guideline 2.1. Someone with an
    /// empty Wallet is offered the option and sent to Wallet to add a card (see
    /// `collectPayment`), which is what Apple expects.
    var supportsPayment: Bool { PKPaymentAuthorizationController.canMakePayments() }

    /// Presents the wallet and waits for the person to finish with it. Must
    /// be reached straight from their tap — Apple won't present the sheet
    /// after asynchronous work, which is why the order is created inside it.
    @MainActor
    func collectPayment(_ request: WidgetPaymentRequest) async throws -> WidgetPaymentResult {
        guard let presenter = presentingViewController else {
            throw WidgetAPIError(status: 500, code: "no_presenter", message: "Couldn't show Apple Pay.")
        }
        // The option is offered on any Apple Pay device, so this is where an
        // empty Wallet is handled: send them to add a card rather than
        // presenting a sheet that can't be paid. `openPaymentSetup` returns
        // immediately — the card is added in Wallet, then they come back and
        // tap Send again.
        guard StripeAPI.deviceSupportsApplePay() else {
            PKPassLibrary().openPaymentSetup()
            throw WidgetAPIError(status: 400, code: "apple_pay_no_card",
                                 message: "Add a card to Apple Wallet, then tap Send again.")
        }
        let coordinator = ApplePayCoordinator(clientSecret: request.clientSecret)
        return try await coordinator.present(request, from: presenter)
    }

}
