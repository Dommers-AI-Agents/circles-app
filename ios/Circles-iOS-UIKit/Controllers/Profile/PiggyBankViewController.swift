import UIKit

/// myPiggyBank: the FavCoin balance and history. Lives beside the store-loyalty
/// Rewards tab in the '$' section — a parallel system, not an extension of it.
///
/// Positioning (owner decision, 2026-08-03): FavCoin is presented as a crypto
/// coin on the Cactus Blockchain whose value is whatever users assign them —
/// the earlier "valueless collectible" framing is retired. On-chain claiming
/// is still a future phase; the copy says "coming soon" and the claim button
/// stays inert until Phase 4 ships.
final class PiggyBankViewController: BaseViewController {

    override var enablesPullToRefresh: Bool { true }

    private var bank: PiggyBank?
    private var activeClaim: PiggyActiveClaim?
    private var events: [PiggyLedgerEvent] = []
    private var payloadConfig: PiggyBankConfigPayload?

    private var claimsEnabled: Bool { payloadConfig?.claimsEnabled == true }

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

    // The story under the hero number, one plain sentence per line:
    // piggy balance / safe on the blockchain (tappable) / clearing. Rows are
    // rebuilt on every render; zero-lines simply don't appear.
    private let breakdownStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private func makeBreakdownRow(_ text: String, emphasized: Bool = false, tappable: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = tappable ? "\(text) ›" : text
        label.font = .systemFont(ofSize: emphasized ? 17 : 15, weight: emphasized ? .bold : .semibold)
        label.textColor = .white
        label.isUserInteractionEnabled = tappable
        return label
    }

    // Linked-wallet row under the claim button: shows the truncated address,
    // taps into the link/change flow.
    private lazy var walletButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 12)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.8), for: .normal)
        button.addTarget(self, action: #selector(walletButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // "What do these numbers mean?" — clearing vs. confirmed confuses every
    // first-time earner, so the answer is one tap away on the card itself.
    private lazy var infoButton: UIButton = {
        let button = UIButton(type: .detailDisclosure)
        button.tintColor = .white
        button.addTarget(self, action: #selector(piggyInfoTapped), for: .touchUpInside)
        button.accessibilityLabel = "About your Piggy Bank"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var claimButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Claim to Cactus Wallet — coming soon")
        // The header card is Colors.primary — the factory's primary-on-primary
        // styling vanishes against it, so this button goes white-on-blue.
        button.setTitleColor(.white, for: .normal)
        button.layer.borderColor = UIColor.white.cgColor
        button.isEnabled = false
        button.alpha = 0.6
        button.addTarget(self, action: #selector(claimTapped), for: .touchUpInside)
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
        [piggyArtLabel, confirmedLabel, confirmedCaptionLabel, breakdownStack, claimButton, walletButton, infoButton].forEach { headerView.addSubview($0) }

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

            infoButton.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            infoButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),

            confirmedLabel.topAnchor.constraint(equalTo: piggyArtLabel.bottomAnchor, constant: 4),
            confirmedLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            confirmedCaptionLabel.topAnchor.constraint(equalTo: confirmedLabel.bottomAnchor, constant: 0),
            confirmedCaptionLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),

            breakdownStack.topAnchor.constraint(equalTo: confirmedCaptionLabel.bottomAnchor, constant: 14),
            breakdownStack.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            breakdownStack.leadingAnchor.constraint(greaterThanOrEqualTo: headerView.leadingAnchor, constant: 16),
            breakdownStack.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -16),

            claimButton.topAnchor.constraint(equalTo: breakdownStack.bottomAnchor, constant: 14),
            claimButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            claimButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),

            walletButton.topAnchor.constraint(equalTo: claimButton.bottomAnchor, constant: 4),
            walletButton.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            walletButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -12),

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

    @objc private func piggyInfoTapped() {
        let hours = payloadConfig?.clearingWindowHours ?? 48
        let threshold = payloadConfig?.minConfirmedToClaim ?? 50
        let lifetime = bank.map { "\n\nLifetime earned: \(PiggyBankFormatting.coins($0.lifetimeCoins))." } ?? ""
        AlertPresenter.showInfo(
            title: "How your Piggy Bank works",
            message: """
            1️⃣ Earn — you get FavCoins for building FavCircles: adding places, creating circles, connecting with friends. "How to earn" below shows what each action pays.

            2️⃣ Clear — new coins wait up to \(hours) hours while we make sure the action sticks (the place you added is still there, for example). Then they land in your piggy bank automatically. If something is undone before it clears, those coins quietly vanish.

            3️⃣ Claim — \(claimsEnabled
                ? "once you have \(threshold), tap Claim to move your coins to your own Cactus Wallet. That puts them on the Cactus blockchain, where they're yours alone — FavCircles can't move or take them."
                : "moving your coins to your own Cactus Wallet is coming soon.")

            FavCoin is a real crypto coin. Its value is whatever people choose to give it — store owners may offer prizes for them, and what you do with yours is up to you.\(lifetime)
            """,
            from: self,
            linkTitle: "Learn more at cactus-network.net",
            linkURL: URL(string: "https://cactus-network.net")
        )
    }

    // MARK: - Data

    /// While a claim is in flight the server settles it within minutes; poll
    /// so the screen flips to "settled" without a manual refresh. One shot
    /// per render — each refresh re-arms only if the claim is still moving.
    private var inFlightRefreshArmed = false
    private func scheduleInFlightRefresh() {
        guard activeClaim != nil, !inFlightRefreshArmed else { return }
        inFlightRefreshArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self else { return }
            self.inFlightRefreshArmed = false
            guard self.view.window != nil, self.activeClaim != nil else { return }
            self.loadData()
        }
    }

    override func loadData(completion: (() -> Void)? = nil) {
        PiggyBankAPIService.shared.getPiggyBank { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { completion?(); return }
                switch result {
                case .success(let response):
                    self.bank = response.bank
                    self.activeClaim = response.activeClaim
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
        // Hero = every coin the user owns, wherever it lives. A piggy-only
        // hero read "0 FavCoins" the moment a claim swept the balance — the
        // worst possible message right after the feature's proudest moment.
        let inFlight = activeClaim?.coins ?? 0
        let total = bank.confirmedCoins + bank.pendingCoins + bank.settledOnChain + inFlight
        confirmedLabel.text = "\(total)"
        // FavCoin follows the Bitcoin convention: the currency's name is
        // singular, a count of units takes the plural.
        confirmedCaptionLabel.text = "your \(PiggyBankFormatting.coinUnit(total))"

        // The story, one plain line each; zero-lines vanish — including the
        // piggy line ("290 … 0 in your piggy bank" read as a contradiction).
        breakdownStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if bank.confirmedCoins > 0 {
            breakdownStack.addArrangedSubview(
                makeBreakdownRow("🐷 \(bank.confirmedCoins) in your piggy bank", emphasized: true))
        }
        if bank.settledOnChain > 0 {
            let row = makeBreakdownRow("🔒 \(bank.settledOnChain) safe on the blockchain", tappable: true)
            row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onChainRowTapped)))
            breakdownStack.addArrangedSubview(row)
        }
        if bank.pendingCoins > 0 {
            breakdownStack.addArrangedSubview(makeBreakdownRow(
                "🕐 \(bank.pendingCoins) clearing — in your piggy within \(payloadConfig?.clearingWindowHours ?? 48)h"))
        }

        renderClaimControls(bank: bank)
        renderActivity()
        scheduleInFlightRefresh()
        renderEarnGuide()
    }

    private func renderClaimControls(bank: PiggyBank) {
        let threshold = payloadConfig?.minConfirmedToClaim ?? 500

        guard claimsEnabled else {
            // Phase 4 not switched on server-side: keep the inert affordance.
            walletButton.isHidden = true
            claimButton.isEnabled = false
            if bank.confirmedCoins >= threshold {
                claimButton.setTitle("Claim to Cactus Wallet — coming soon", for: .normal)
                claimButton.alpha = 0.8
            } else {
                claimButton.setTitle("Claim unlocks at \(threshold) \(PiggyBankFormatting.coinUnit(threshold))", for: .normal)
                claimButton.alpha = 0.6
            }
            return
        }

        walletButton.isHidden = false
        if let address = bank.walletAddress {
            walletButton.setTitle("🔗 \(Self.truncateAddress(address)) · change", for: .normal)
        } else {
            walletButton.setTitle("🔗 Link your Cactus Wallet", for: .normal)
        }

        if let claim = activeClaim {
            claimButton.setTitle("🚀 \(PiggyBankFormatting.coins(claim.coins)) on the way to your wallet", for: .normal)
            claimButton.isEnabled = false
            claimButton.alpha = 0.8
        } else if bank.confirmedCoins >= threshold {
            claimButton.setTitle("Claim \(PiggyBankFormatting.coins(bank.confirmedCoins)) to your wallet", for: .normal)
            claimButton.isEnabled = true
            claimButton.alpha = 1.0
        } else {
            claimButton.setTitle("Claim unlocks at \(threshold) \(PiggyBankFormatting.coinUnit(threshold))", for: .normal)
            claimButton.isEnabled = false
            claimButton.alpha = 0.6
        }
    }

    /// cac1abcdefgh…wxyz — enough to recognize, short enough for one line
    private static func truncateAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return "\(address.prefix(8))…\(address.suffix(4))"
    }

    // MARK: - Claim flow

    @objc private func walletButtonTapped() {
        promptLinkWallet()
    }

    private func promptLinkWallet(thenClaim: Bool = false) {
        AlertPresenter.showTextInput(
            title: "Link your Cactus Wallet",
            message: "Paste your wallet's receive address (starts with cac1). Coins claimed there belong to you alone — FavCircles can't move or recover them.",
            placeholder: "cac1…",
            from: self
        ) { [weak self] input in
            guard let self = self,
                  let address = input?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !address.isEmpty else { return }
            PiggyBankAPIService.shared.linkWallet(address: address) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        if thenClaim {
                            self.loadData { self.confirmAndClaim() }
                        } else {
                            self.showSuccess("Wallet linked")
                            self.loadData()
                        }
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    @objc private func claimTapped() {
        guard claimsEnabled, activeClaim == nil, let bank = bank else { return }
        guard bank.walletAddress != nil else {
            promptLinkWallet(thenClaim: true)
            return
        }
        confirmAndClaim()
    }

    private func confirmAndClaim() {
        guard let bank = bank, let address = bank.walletAddress else { return }
        let fee = payloadConfig?.claimFeeCoins ?? 0
        var message = "Send \(PiggyBankFormatting.coins(bank.confirmedCoins)) to your Cactus Wallet:\n\(Self.truncateAddress(address))"
        if fee > 0 { message += "\n\nNetwork fee: \(PiggyBankFormatting.coins(fee)) (deducted from the claim)" }
        message += "\n\nOn-chain transfers can't be reversed."
        AlertPresenter.showConfirmation(
            title: "Claim your FavCoins?",
            message: message,
            confirmTitle: "Claim",
            from: self,
            onConfirm: { [weak self] in
            guard let self = self else { return }
            PiggyBankAPIService.shared.claim { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.showSuccess("🚀 Your FavCoins are on the way!")
                        self.loadData()
                    case .failure(let error):
                        self.showError(error)
                        self.loadData()  // 409 etc. → re-sync the button state
                    }
                }
            }
        })
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
        for (index, event) in events.enumerated() {
            let row = makeActivityRow(event)
            // Settled claims open their on-chain proof.
            if event.isClaim && event.isSettled {
                row.tag = index
                row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(claimRowTapped(_:))))
            }
            activityStack.addArrangedSubview(row)
        }
    }

    /// The "safe on the blockchain" line opens the proof: every completed
    /// transfer, each linking to its coin on the Cactus explorer.
    @objc private func onChainRowTapped() {
        let settled = events.filter { $0.isClaim && $0.isSettled }
        let sheet = OnChainCoinsViewController(claims: settled, totalCoins: bank?.settledOnChain ?? 0)
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    @objc private func claimRowTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag, index < events.count else { return }
        let event = events[index]
        // The settled row carries a deep link to the created coin — the only
        // page on the Cactus explorer that can prove a CAT transfer (there is
        // no /tx/ route, and CAT wrapping hides coins from address pages).
        let link = event.explorerUrl ?? payloadConfig?.explorerBaseUrl
            ?? "https://explorer.cactus-network.net/#/"
        AlertPresenter.showInfo(
            title: "On-chain transfer",
            message: "\(PiggyBankFormatting.coins(event.coins)) were sent to your Cactus Wallet.\(event.txId != nil ? "\n\nTransaction: \(event.txId!)" : "")",
            from: self,
            linkTitle: event.explorerUrl != nil ? "View coin on Cactus explorer" : "Open Cactus explorer",
            linkURL: URL(string: link)
        )
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
        if event.isClaim {
            if event.isClaimInFlight { parts.append("on the way to your wallet") }
            if event.isSettled { parts.append("✓ in your wallet · tap for proof") }
            if event.isClaimFailed { parts.append("didn't go through — coins returned") }
        }
        subtitle.text = parts.joined(separator: " · ")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = Constants.Colors.secondaryLabel
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let coins = UILabel()
        if event.isClaim {
            // Coins leaving the in-app balance for the user's own wallet.
            coins.text = event.isClaimFailed ? "—" : "→⛓ \(event.coins)"
            coins.font = .systemFont(ofSize: 15, weight: .bold)
            coins.textColor = event.isSettled ? Constants.Colors.primary : Constants.Colors.secondaryLabel
        } else {
            coins.text = event.isReversed ? "—" : "+\(event.coins)"
            coins.font = .systemFont(ofSize: 15, weight: .bold)
            coins.textColor = event.isPending
                ? Constants.Colors.secondaryLabel     // muted while clearing
                : (event.isReversed ? Constants.Colors.secondaryLabel : Constants.Colors.primary)
        }
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
            ("REFERRAL_SIGNUP", "Refer a friend who joins"),
            ("CREATE_CIRCLE", "Create a circle (3+ places)"),
            ("PLACE_ADOPTED", "A friend saves a place you shared"),
            ("PROFILE_COMPLETED", "Complete your profile (photo + bio)"),
            ("ADD_PLACE", "Add a place"),
            ("SHARE_CIRCLE", "Share a circle with a friend"),
            ("CONNECTION_ACCEPTED", "Make a new connection"),
            ("MOMENT_POSTED", "Post a Moment"),
            ("CHECK_IN", "Check in at a place"),
            ("PLACE_PHOTO", "Add your first photo of a place"),
            ("PLACE_LIKED", "Like a place (first time)"),
            ("PLACE_COMMENT", "Comment on a place (first time)"),
            ("USER_FOLLOWED", "Follow someone new"),
            ("SUGGESTION_POSTED", "Post a suggestion")
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

// MARK: - On-chain proof sheet

/// "Your coins on the Cactus blockchain" — one row per completed transfer,
/// each opening its coin on the Cactus explorer. CAT wrapping keeps these
/// coins off the explorer's address pages, so per-transfer coin links are the
/// only on-chain proof surface; the live balance lives in the user's own
/// Cactus Wallet app.
final class OnChainCoinsViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate {

    override var loadsDataOnViewDidLoad: Bool { false }

    private let claims: [PiggyLedgerEvent]
    private let totalCoins: Int

    init(claims: [PiggyLedgerEvent], totalCoins: Int) {
        self.claims = claims
        self.totalCoins = totalCoins
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.dataSource = self
        table.delegate = self
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background

        let header = UILabel()
        header.text = "🔒 \(totalCoins) FavCoins on the Cactus blockchain"
        header.font = .systemFont(ofSize: 17, weight: .bold)
        header.textAlignment = .center
        header.numberOfLines = 0
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(claims.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        guard !claims.isEmpty else {
            cell.textLabel?.text = "Transfers appear here after you claim"
            cell.textLabel?.textColor = Constants.Colors.secondaryLabel
            cell.selectionStyle = .none
            return cell
        }
        let claim = claims[indexPath.row]
        var dateText = ""
        if let date = claim.createdDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            dateText = formatter.string(from: date)
        }
        cell.textLabel?.text = "\(PiggyBankFormatting.coins(claim.coins)) · \(dateText)"
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cell.detailTextLabel?.text = claim.explorerUrl != nil
            ? "✓ confirmed · view the coin on the explorer"
            : "✓ confirmed"
        cell.detailTextLabel?.textColor = Constants.Colors.secondaryLabel
        cell.accessoryType = claim.explorerUrl != nil ? .disclosureIndicator : .none
        cell.selectionStyle = claim.explorerUrl != nil ? .default : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !claims.isEmpty,
              let urlString = claims[indexPath.row].explorerUrl,
              let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "These coins live in your own Cactus Wallet — FavCircles can't move or take them. Your wallet app shows the full balance; each transfer above links to its coin on the public explorer."
    }
}
