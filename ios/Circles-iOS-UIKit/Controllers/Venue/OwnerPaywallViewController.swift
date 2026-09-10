import UIKit
import StoreKit

/// Paywall for FavCircles Business — the store-owner subscription that unlocks
/// the full stats dashboard, announcements, offers, and the loyalty program.
/// Separate StoreKit subscription group from consumer premium. Presented from
/// VenueManageViewController / VenueDashboardViewController when a free owner
/// taps a locked tool.
class OwnerPaywallViewController: BaseViewController {

    // MARK: - Properties

    private var businessProducts: [SubscriptionProduct] = []

    /// The venue this subscription is being purchased for. Each store
    /// subscribes separately — the backend binds the entitlement to this venue.
    var venueId: String?

    /// Called after a successful purchase so the presenting screen can unlock
    var onSubscribed: (() -> Void)?

    // MARK: - UI Elements

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.medium
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let headerLabel: UILabel = {
        let label = UILabel()
        label.text = "FavCircles Business"
        label.font = UIFont.systemFont(ofSize: 26, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "How do you keep your customers coming back today? Turn savers and followers into regulars."
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let featuresStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.small
        return stack
    }()

    private let productsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.small
        return stack
    }()

    private lazy var restoreButton = UIButton.secondaryButton(title: "Restore Purchases")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Business"
        view.backgroundColor = Constants.Colors.background

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(headerLabel)
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.setCustomSpacing(Constants.Spacing.large, after: subtitleLabel)
        contentStack.addArrangedSubview(featuresStack)
        contentStack.setCustomSpacing(Constants.Spacing.large, after: featuresStack)
        contentStack.addArrangedSubview(productsStack)
        contentStack.addArrangedSubview(restoreButton)

        // Functional Terms/Privacy links are REQUIRED on subscription screens
        // (App Review 3.1.2(c)); this screen had none.
        let legalTextView = LegalLinks.makeLegalTextView()
        legalTextView.attributedText = LegalLinks.agreementText(
            "Subscriptions renew automatically until canceled in Settings. By subscribing, you agree to our Terms of Use (EULA) and Privacy Policy.",
            termsPhrase: "Terms of Use (EULA)",
            fontSize: 12,
            color: .secondaryLabel
        )
        legalTextView.textAlignment = .center
        contentStack.addArrangedSubview(legalTextView)

        BusinessFeatures.features.forEach { featuresStack.addArrangedSubview(makeFeatureRow($0)) }
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Constants.Spacing.large),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Constants.Spacing.large),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Constants.Spacing.large),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Constants.Spacing.large),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Constants.Spacing.large)
        ])
    }

    // MARK: - BaseViewController

    override func loadData(completion: (() -> Void)? = nil) {
        Task { @MainActor in
            do {
                try await SubscriptionService.shared.loadProducts()
                self.businessProducts = SubscriptionService.shared.businessProducts
                self.renderProducts()
            } catch {
                self.renderProducts() // shows the unavailable note
                Logger.error("Failed to load business products: \(error)")
            }
            completion?()
        }
    }

    // MARK: - Rendering

    private func makeFeatureRow(_ feature: PremiumFeatures.Feature) -> UIView {
        let row = UIView()

        let icon = UIImageView(image: UIImage(systemName: feature.iconName))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = feature.title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descriptionLabel = UILabel()
        descriptionLabel.text = feature.description
        descriptionLabel.font = UIFont.systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(icon)
        row.addSubview(titleLabel)
        row.addSubview(descriptionLabel)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.topAnchor.constraint(equalTo: row.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Constants.Spacing.small),
            titleLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            descriptionLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])
        return row
    }

    private func renderProducts() {
        productsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !businessProducts.isEmpty else {
            let note = UILabel()
            note.text = "Business plans aren't available right now."
            note.font = UIFont.systemFont(ofSize: 14)
            note.textColor = .secondaryLabel
            note.textAlignment = .center
            note.numberOfLines = 0
            productsStack.addArrangedSubview(note)

            // Product loads fail transiently (network, StoreKit hiccups) —
            // give the owner a way back that isn't pop-and-repush
            let retryButton = UIButton.secondaryButton(title: "Try Again")
            retryButton.addAction(UIAction { [weak self] _ in
                self?.loadData()
            }, for: .touchUpInside)
            productsStack.addArrangedSubview(retryButton)
            return
        }

        for product in businessProducts {
            let button = UIButton.primaryButton(title: product.tierName)
            // Two lines — plan name over price/trial. The single-line form
            // truncated the price out of the middle ("$…fter 3 months free trial").
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let title = NSMutableAttributedString(
                string: product.tierName,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
            )
            title.append(NSAttributedString(
                string: "\n" + product.subscriptionDescription,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                    .paragraphStyle: paragraph
                ]
            ))
            button.setAttributedTitle(title, for: .normal)
            button.titleLabel?.numberOfLines = 2
            button.addAction(UIAction { [weak self] _ in
                self?.purchase(product)
            }, for: .touchUpInside)
            productsStack.addArrangedSubview(button)
        }
    }

    // MARK: - Purchase / Restore

    private func purchase(_ product: SubscriptionProduct) {
        let loading = AlertPresenter.showLoading(message: "Processing...", from: self)
        Task { @MainActor in
            do {
                let result = try await SubscriptionService.shared.purchase(product, venueId: venueId)
                loading.dismiss(animated: true) {
                    switch result {
                    case .cancelled:
                        break
                    case .pending:
                        AlertPresenter.showSuccess(
                            title: "Approval Requested",
                            message: "This purchase is waiting for approval (Ask to Buy). Your store tools unlock automatically once it's approved.",
                            from: self
                        )
                    case .success(_, let backendSynced):
                        if backendSynced {
                            AlertPresenter.showSuccess(
                                title: "Welcome to Business",
                                message: "Your store tools are unlocked — dashboard, announcements, offers, and loyalty.",
                                from: self
                            ) { [weak self] in
                                self?.onSubscribed?()
                                self?.navigationController?.popViewController(animated: true)
                            }
                        } else {
                            // Apple charged them but our server hasn't recorded
                            // it yet — the unfinished transaction re-syncs on
                            // next launch, so be honest instead of celebrating.
                            AlertPresenter.showSuccess(
                                title: "Payment Confirmed",
                                message: "Your payment went through, but activating your store tools is taking longer than usual. They'll unlock automatically within a few minutes — reopen this store's dashboard to check.",
                                from: self
                            ) { [weak self] in
                                self?.onSubscribed?()
                                self?.navigationController?.popViewController(animated: true)
                            }
                        }
                    }
                }
            } catch {
                loading.dismiss(animated: true) {
                    self.showError(error)
                }
            }
        }
    }

    @objc private func restoreTapped() {
        let loading = AlertPresenter.showLoading(message: "Restoring...", from: self)
        Task { @MainActor in
            do {
                try await SubscriptionService.shared.restorePurchases(venueId: venueId)
                // Apple only knows this Apple ID has A business subscription —
                // the server knows which store it's bound to. Confirm against
                // the server before telling the owner this venue is active.
                let hasAppleSub = SubscriptionService.shared.isBusinessSubscriber
                self.confirmRestoreAgainstServer(hasAppleSub: hasAppleSub, loading: loading)
            } catch {
                loading.dismiss(animated: true) {
                    self.showError(error)
                }
            }
        }
    }

    private func confirmRestoreAgainstServer(hasAppleSub: Bool, loading: UIAlertController) {
        guard let venueId = venueId else {
            loading.dismiss(animated: true) {
                if hasAppleSub {
                    AlertPresenter.showSuccess(
                        title: "Restored",
                        message: "Your business subscription is active.",
                        from: self
                    ) { [weak self] in
                        self?.onSubscribed?()
                        self?.navigationController?.popViewController(animated: true)
                    }
                } else {
                    AlertPresenter.showError(message: "No business subscription found to restore.", from: self)
                }
            }
            return
        }

        RewardsService.shared.getMyVenues { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let mine = (try? result.get())?.first { $0.venueId == venueId }
                loading.dismiss(animated: true) {
                    if mine?.ownerPremium == true {
                        AlertPresenter.showSuccess(
                            title: "Restored",
                            message: "Your business subscription is active for this store.",
                            from: self
                        ) { [weak self] in
                            self?.onSubscribed?()
                            self?.navigationController?.popViewController(animated: true)
                        }
                    } else if hasAppleSub {
                        AlertPresenter.showError(
                            message: "Your Apple ID has a Business subscription, but it's assigned to a different store. Each store needs its own subscription.",
                            from: self
                        )
                    } else {
                        AlertPresenter.showError(message: "No business subscription found to restore.", from: self)
                    }
                }
            }
        }
    }
}
