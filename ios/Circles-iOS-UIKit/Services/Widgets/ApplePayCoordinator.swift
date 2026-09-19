import UIKit
import PassKit
import StripeApplePay
import FavWidgetsCore

/// Bridges the widget package's `collectPayment` to Stripe's Apple Pay
/// context.
///
/// Apple Pay is the only payment method the app offers, and it's the only
/// one a physical-goods purchase is allowed to use — App Store Review
/// Guideline 3.1.3(e) requires physical goods to be paid for outside
/// in-app purchase. Stripe is the processor behind the wallet token.
///
/// The object keeps itself alive for the length of the sheet: Stripe's
/// context holds only a weak delegate, so without the self-reference this
/// would deallocate the moment `collectPayment` suspends and the payment
/// would never complete.
final class ApplePayCoordinator: NSObject, ApplePayContextDelegate {
    private let clientSecret: @Sendable () async throws -> String
    private var continuation: CheckedContinuation<WidgetPaymentResult, Error>?
    private var selfReference: ApplePayCoordinator?
    /// Resuming a continuation twice traps, and these are delegate callbacks
    /// we don't control the number of. Every resume goes through this.
    private let resumeOnce = OnceFlag()
    /// Converts "the sheet never appeared" into an error instead of an await
    /// that never returns. See `finish` for why that case is reachable.
    private var watchdog: Task<Void, Never>?
    /// An error raised while creating the order, kept so the caller is told
    /// what actually went wrong instead of a generic payment failure.
    private var secretError: Error?

    init(clientSecret: @escaping @Sendable () async throws -> String) {
        self.clientSecret = clientSecret
    }

    @MainActor
    func present(_ request: WidgetPaymentRequest, from presenter: UIViewController) async throws -> WidgetPaymentResult {
        StripeAPI.defaultPublishableKey = request.publishableKey

        let paymentRequest = StripeAPI.paymentRequest(
            withMerchantIdentifier: request.applePayMerchantId,
            country: "US",
            currency: request.currency.uppercased()
        )
        // The final line item is the one the wallet prefixes with "Pay", so
        // it has to read as the business, not the product.
        paymentRequest.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: request.summaryLabel,
                amount: NSDecimalNumber(value: request.amountCents).dividing(by: 100)
            ),
            PKPaymentSummaryItem(
                label: request.merchantDisplayName,
                amount: NSDecimalNumber(value: request.amountCents).dividing(by: 100)
            )
        ]

        guard let context = STPApplePayContext(paymentRequest: paymentRequest, delegate: self) else {
            // Almost always a configuration problem: no merchant certificate,
            // or a merchant id that doesn't match the entitlement.
            throw WidgetAPIError(status: 500, code: "apple_pay_unavailable",
                                 message: "Apple Pay isn't set up on this device.")
        }

        let window = presenter.viewIfLoaded?.window
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.selfReference = self
            context.presentApplePay(from: window)
            startWatchdog()
        }
    }

    /// Stripe presents the wallet through PKPaymentAuthorizationController and
    /// discards its "did it actually present" result. So when presentation
    /// fails — a merchant certificate that doesn't match the entitlement is the
    /// likely cause — no delegate method is ever called and this await would
    /// never return. The compose screen sits disabled behind a spinner and the
    /// only way out is force-quitting the app.
    ///
    /// The window is deliberately long. Someone can legitimately stare at the
    /// Apple Pay sheet for minutes, and cutting off a real payment mid-thought
    /// would be far worse than the hang this exists to prevent.
    // There is deliberately NO short "did the sheet appear?" probe here, and
    // there was one for a day. Stripe presents through
    // PKPaymentAuthorizationController, whose sheet is a system remote UI that
    // never enters the app's presentedViewController chain — so a probe that
    // compared that chain saw "nothing presented" on every payment and, six
    // seconds in, resumed the continuation with "Apple Pay didn't open" while
    // the person was mid-Face-ID. The sheet carried on independently, the
    // charge went through, and the app had already told them it failed and
    // that they hadn't been charged. Stripe discards the one real presentation
    // signal (`authorizationController.present { presented in … }`), so with
    // the information available a fast probe cannot be made safe. A slow
    // watchdog that never lies beats a fast one that sometimes does.

    private func startWatchdog() {
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            // Bound before use: capturing the weak var itself into the
            // MainActor closure is an error under Swift 6.
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                self.finish(.failure(WidgetAPIError(
                    status: 500, code: "apple_pay_unavailable",
                    message: "Apple Pay didn't open. Check that Apple Pay is set up on this device.")))
            }
        }
    }

    /// The single exit. Whichever of the delegate callbacks, or the watchdog,
    /// gets here first wins; the rest are no-ops.
    private func finish(_ result: Result<WidgetPaymentResult, Error>) {
        guard resumeOnce.claim() else { return }
        watchdog?.cancel()
        watchdog = nil
        let continuation = self.continuation
        self.continuation = nil
        selfReference = nil
        continuation?.resume(with: result)
    }

    // MARK: - ApplePayContextDelegate

    /// The wallet has authorized. Only now do we create the order, because
    /// Apple won't present the sheet if a network call runs before it.
    func applePayContext(
        _ context: STPApplePayContext,
        didCreatePaymentMethod paymentMethod: StripeAPI.PaymentMethod,
        paymentInformation: PKPayment,
        completion: @escaping STPIntentClientSecretCompletionBlock
    ) {
        Task {
            do {
                completion(try await clientSecret(), nil)
            } catch {
                secretError = error
                completion(nil, error)
            }
        }
    }

    func applePayContext(
        _ context: STPApplePayContext,
        didCompleteWith status: STPApplePayContext.PaymentStatus,
        error: Error?
    ) {
        let failed = WidgetAPIError(status: 500, code: "payment_failed",
                                    message: "The payment didn't go through.")
        switch status {
        case .success:
            // Note this also covers a PaymentIntent left in `requires_capture`
            // rather than `succeeded`: the money is held, not taken, which is
            // exactly what a printed postcard order wants.
            finish(.success(.completed))
        case .userCancellation:
            // Dismissing the wallet is a choice, not a failure. Nothing was
            // authorized and nothing should be reported as wrong.
            finish(.success(.canceled))
        case .error:
            finish(.failure(secretError ?? error ?? failed))
        @unknown default:
            finish(.failure(failed))
        }
    }
}
