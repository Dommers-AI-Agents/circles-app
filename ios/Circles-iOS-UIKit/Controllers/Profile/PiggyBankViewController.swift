import UIKit

/// myPiggyBank: the FavCoin balance and history. Lives beside the store-loyalty
/// Rewards tab in the '$' section — a parallel system, not an extension of it.
///
/// Coins are deliberately valueless: the copy talks about coins and clearing,
/// never money. Claiming (to a Cactus wallet) is a future phase — the button
/// exists as an inert affordance so the destination is legible.
final class PiggyBankViewController: BaseViewController {

    override var enablesPullToRefresh: Bool { true }

    private var bank: PiggyBank?
    private var events: [PiggyLedgerEvent] = []
    private var payloadConfig: PiggyBankConfigPayload?

    // MARK: - UI

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.primary
        view.layer.cornerRadius = 16
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let piggyArtLabel: UILabel = {
        let label = UILabel()
        label.text = "🐷"
        label.font = .systemFont(ofSize: 56)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let confirmedLabel: UILabel = {
        let label = UILabel()
        label.text = "—"
        label.font = .systemFont(ofSize: 44, weight: .heavy)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let confirmedCaptionLabel: UILabel = {
        let label = UILabel()
        label.text = "FavCoins"
        label.font = .systemFont(ofSize: 15)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let pendingLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let lifetimeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = UIColor.white.withAlphaComponent(0.75)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var claimButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Claim to Cactus Wallet — coming soon")
        button.isEnabled = false
        button.alpha = 0.6
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let activityTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Recent activity"
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let activityStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let earnTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "How to earn"
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let earnStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "My Piggy Bank"
        view.backgroundColor = Constants.Colors.background
        setupLayout()
    }

    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        [headerView, activityTitleLabel, activityStack, earnTitleLabel, earnStack].forEach { contentView.addSubview($0) }
        [piggyArtLabel, confirmedLabel, confirmedCaptionLabel, pendingLabel, lifetimeLabel, claimButton].forEach { headerView.addSubview($0) }

        scrollView.refreshControl = refreshControl

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            piggyArtLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 18),
            piggyArtLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),

            confirmedLabel.topAnchor.constraint(equalTo: piggyArtLabel.bottomAnchor, constant: 4),
            confirmedLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            confirmedCaptionLabel.topAnchor.constraint(equalTo: confirmedLabel.bottomAnchor, constant: 0),
            confirmedCaptionLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),

            pendingLabel.topAnchor.constraint(equalTo: confirmedCaptionLabel.bottomAnchor, constant: 12),
            pendingLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            lifetimeLabel.topAnchor.constraint(equalTo: pendingLabel.bottomAnchor, constant: 2),
            lifetimeLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),

            claimButton.topAnchor.constraint(equalTo: lifetimeLabel.bottomAnchor, constant: 14),
            claimButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            claimButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            claimButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -18),

            activityTitleLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24),
            activityTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            activityStack.topAnchor.constraint(equalTo: activityTitleLabel.bottomAnchor, constant: 8),
            activityStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            activityStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            earnTitleLabel.topAnchor.constraint(equalTo: activityStack.bottomAnchor, constant: 28),
            earnTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            earnStack.topAnchor.constraint(equalTo: earnTitleLabel.bottomAnchor, constant: 8),
            earnStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            earnStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            earnStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
    }

    // MARK: - Data

    override func loadData(completion: (() -> Void)? = nil) {
        PiggyBankAPIService.shared.getPiggyBank { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { completion?(); return }
                switch result {
                case .success(let response):
                    self.bank = response.bank
                    self.events = response.events
                    self.payloadConfig = response.config
                    self.render()
                case .failure(let error):
                    self.showError(error)
                }
                completion?()
            }
        }
    }

    private func render() {
        guard let bank = bank else { return }
        confirmedLabel.text = "\(bank.confirmedCoins)"
        pendingLabel.text = bank.pendingCoins > 0
            ? "🕐 \(bank.pendingCoins) pending — clears within \(payloadConfig?.clearingWindowHours ?? 48)h"
            : "Nothing pending"
        lifetimeLabel.text = "Lifetime earned: \(bank.lifetimeCoins)"

        // Inert claim affordance: legible destination, no network call. Only
        // "unlocks" visually at the threshold, and still does nothing (Phase 4).
        let threshold = payloadConfig?.minConfirmedToClaim ?? 500
        if bank.confirmedCoins >= threshold {
            claimButton.setTitle("Claim to Cactus Wallet — coming soon", for: .normal)
            claimButton.alpha = 0.8
        } else {
            claimButton.setTitle("Claim unlocks at \(threshold) FavCoins", for: .normal)
            claimButton.alpha = 0.6
        }

        renderActivity()
        renderEarnGuide()
    }

    private func renderActivity() {
        activityStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if events.isEmpty {
            let empty = UILabel()
            empty.text = "Coins you earn will show up here."
            empty.font = .systemFont(ofSize: 14)
            empty.textColor = Constants.Colors.secondaryLabel
            activityStack.addArrangedSubview(empty)
            return
        }
        for event in events {
            activityStack.addArrangedSubview(makeActivityRow(event))
        }
    }

    private func makeActivityRow(_ event: PiggyLedgerEvent) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = event.displayTitle
        title.font = .systemFont(ofSize: 15, weight: .medium)
        // Reversed rows read as struck history, pending as "in flight".
        title.textColor = event.isReversed ? Constants.Colors.secondaryLabel : Constants.Colors.label
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        var parts: [String] = []
        if let date = event.createdDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append(formatter.string(from: date))
        }
        if event.isPending { parts.append("clearing") }
        if event.isReversed { parts.append("reversed") }
        subtitle.text = parts.joined(separator: " · ")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = Constants.Colors.secondaryLabel
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let coins = UILabel()
        coins.text = event.isReversed ? "—" : "+\(event.coins)"
        coins.font = .systemFont(ofSize: 15, weight: .bold)
        coins.textColor = event.isPending
            ? Constants.Colors.secondaryLabel     // muted while clearing
            : (event.isReversed ? Constants.Colors.secondaryLabel : Constants.Colors.primary)
        coins.translatesAutoresizingMaskIntoConstraints = false
        coins.setContentHuggingPriority(.required, for: .horizontal)

        row.addSubview(title)
        row.addSubview(subtitle)
        row.addSubview(coins)

        let divider = UIView()
        divider.backgroundColor = Constants.Colors.separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(divider)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: coins.leadingAnchor, constant: -8),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            subtitle.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            coins.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            coins.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            divider.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        return row
    }

    private func renderEarnGuide() {
        earnStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let values = payloadConfig?.coinValues else { return }

        // Config-key → friendly copy, in a deliberate order.
        let guide: [(key: String, text: String)] = [
            ("ADD_PLACE", "Add a place"),
            ("PLACE_ADOPTED", "A friend saves a place you shared"),
            ("CREATE_CIRCLE", "Create a circle (3+ places)"),
            ("SHARE_CIRCLE", "Share a circle with a friend"),
            ("CONNECTION_ACCEPTED", "Make a new connection"),
            ("SUGGESTION_POSTED", "Post a suggestion"),
            ("REFERRAL_SIGNUP", "Refer a friend who joins")
        ]
        for item in guide {
            guard let coins = values[item.key], coins > 0 else { continue }
            let label = UILabel()
            label.font = .systemFont(ofSize: 14)
            label.textColor = Constants.Colors.secondaryLabel
            label.text = "🪙 +\(coins) — \(item.text)"
            earnStack.addArrangedSubview(label)
        }

        let footnote = UILabel()
        footnote.font = .systemFont(ofSize: 12)
        footnote.textColor = Constants.Colors.secondaryLabel
        footnote.numberOfLines = 0
        footnote.text = "New coins clear within \(payloadConfig?.clearingWindowHours ?? 48) hours. Daily limits apply."
        earnStack.addArrangedSubview(footnote)
    }
}
