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

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.selfReference = self
            context.presentApplePay(on: presenter)
        }
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
        let continuation = self.continuation
        self.continuation = nil
        defer { selfReference = nil }

        switch status {
        case .success:
            // Note this also covers a PaymentIntent left in `requires_capture`
            // rather than `succeeded`: the money is held, not taken, which is
            // exactly what a printed postcard order wants.
            continuation?.resume(returning: .completed)
        case .userCancellation:
            // Dismissing the wallet is a choice, not a failure. Nothing was
            // authorized and nothing should be reported as wrong.
            continuation?.resume(returning: .canceled)
        case .error:
            continuation?.resume(throwing: secretError ?? error ?? WidgetAPIError(
                status: 500, code: "payment_failed", message: "The payment didn't go through."))
        @unknown default:
            continuation?.resume(throwing: WidgetAPIError(
                status: 500, code: "payment_failed", message: "The payment didn't go through."))
        }
    }
}
