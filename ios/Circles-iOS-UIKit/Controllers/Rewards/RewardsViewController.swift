import UIKit
import CoreLocation

/// Rewards home: points balance, browsable offers from participating places
/// (saved places first, then nearby), how the program works, and recent
/// activity. Entry points: the $ button on the home screen and the star
/// button on the Profile screen.
class RewardsViewController: BaseViewController {

    /// Coming from a scan (2026-11-02): this store's card goes first,
    /// outlined, with what was just earned
    var highlightVenueId: String?
    var justEarnedPoints: Int?

    // MARK: - Properties

    private var balanceData: RewardBalanceData?
    private var offersData: RewardOffersData?
    private let locationManager = CLLocationManager()
    private var offersCompletion: (() -> Void)?

    // MARK: - UI Elements

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Constants.Colors.primary
        return view
    }()

    private let starImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "dollarsign.circle.fill")
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let balanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "—"
        label.font = UIFont.systemFont(ofSize: 48, weight: .heavy)
        label.textColor = .white
        label.textAlignment = .center
        return label
    }()

    private let balanceCaptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "points to spend on rewards at local stores"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .white.withAlphaComponent(0.9)
        label.textAlignment = .center
        return label
    }()

    // "What are these points?" — same affordance as the Piggy Bank tab's ⓘ,
    // one tap away on the balance card itself.
    private lazy var infoButton: UIButton = {
        let button = UIButton(type: .detailDisclosure)
        button.tintColor = .white
        button.addTarget(self, action: #selector(rewardsInfoTapped), for: .touchUpInside)
        button.accessibilityLabel = "About store points"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // Tappable banner for a voucher that's still counting down — lets users
    // leave the voucher screen and get back to it
    private let activeVoucherBanner: UIControl = {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.backgroundColor = .systemGreen
        control.layer.cornerRadius = 12
        control.clipsToBounds = true
        control.isHidden = true
        return control
    }()

    private let voucherBannerTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.numberOfLines = 1
        return label
    }()

    private let voucherBannerTimeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        label.textColor = .white
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private var voucherBannerHeight: NSLayoutConstraint?
    private var voucherBannerTimer: Timer?

    // Per-store loyalty: points are earned and spent shop by shop, so the
    // balance card's total is display only — these rows are the real
    // spendable buckets. Collapses to zero height until points exist.
    /// "Rewards used": the customer's recent tickets and what became of
    /// them, given or points back (2026-11-01)
    private let ticketsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let storeBalancesStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }()

    private let savedOffersLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Offers at your places"
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let savedOffersStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }()

    private let nearbyOffersLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Nearby offers"
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let nearbyOffersStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }()

    private let howItWorksLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "How it works:"
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let stepsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel

        label.text = """
        📍 Spot a FavCircles sticker at a place you love
        📲 Scan it to open the store and save it to a circle
        🧾 Scan the register card when you buy something — each shop sets its own points, plus a bonus for saving the shop
        🎟 Type in the code from a shop's order card or booth handout
        🏬 Points stay with the shop: earn them at a store, spend them on that store's offers
        🎁 Redeem points for offers right at the counter
        """
        return label
    }()

    private let activityLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Recent activity"
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let activityStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        return stack
    }()

    // MARK: - Lifecycle

    override var enablesPullToRefresh: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Rewards"
        view.backgroundColor = .systemBackground
        setupUI()
    }

    // MARK: - BaseViewController

    override func loadData(completion: (() -> Void)? = nil) {
        loadOffers(completion: completion)
        loadHistory()
        loadTickets()
    }

    // MARK: - Rewards used

    private func loadTickets() {
        RewardsService.shared.fetchRewardTickets { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let data) = result else { return }
                self.updateActiveVoucherBanner()
                self.renderTickets(RewardTicketCopy.shown(data.recent))
            }
        }
    }

    private func renderTickets(_ tickets: [RewardVoucher]) {
        ticketsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !tickets.isEmpty else { return }
        let header = UILabel()
        header.text = "Rewards used"
        header.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        header.textColor = .label
        ticketsStack.addArrangedSubview(header)
        for ticket in tickets.prefix(10) {
            let line = RewardTicketCopy.historyLine(ticket)
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            let icon = UIImageView(image: UIImage(systemName: line.symbol))
            icon.tintColor = line.isOpen ? .systemGreen : (ticket.status == "given" ? .systemGreen : .systemOrange)
            icon.setContentHuggingPriority(.required, for: .horizontal)
            let text = UILabel()
            text.numberOfLines = 2
            text.font = .systemFont(ofSize: 14)
            text.text = line.text
            row.addArrangedSubview(icon)
            row.addArrangedSubview(text)
            if line.isOpen {
                row.isUserInteractionEnabled = true
                let tap = UITapGestureRecognizer(target: self, action: #selector(activeVoucherBannerTapped))
                row.addGestureRecognizer(tap)
            }
            ticketsStack.addArrangedSubview(row)
        }
    }

    // MARK: - Offers loading (with best-effort location for the Nearby section)

    private func loadOffers(completion: (() -> Void)?) {
        offersCompletion = completion
        // BaseViewController.viewDidLoad() triggers loadData() before this
        // class's viewDidLoad body runs, so the delegate MUST be assigned here:
        // requestLocation() with a nil delegate is a runtime assertion crash.
        locationManager.delegate = self
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            // Denied/restricted: nearby section falls back to alphabetical
            fetchOffers(lat: nil, lng: nil)
        }
    }

    private func fetchOffers(lat: Double?, lng: Double?) {
        RewardsService.shared.getOffers(lat: lat, lng: lng) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.offersCompletion?()
                self.offersCompletion = nil
                switch result {
                case .success(let data):
                    self.offersData = data
                    self.balanceLabel.text = "\(data.balance)"
                    // Before the offer rows render — affordability reads these
                    self.updateStoreBalances(data.venueBalances)
                    self.updateOffersUI(with: data)
                case .failure(let error):
                    // Offers are additive — balance/history still render
                    Logger.debug("⚠️ Failed to load offers: \(error)")
                    self.updateOffersUI(with: nil)
                }
            }
        }
    }

    private func loadHistory() {
        RewardsService.shared.getBalance { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    self?.balanceData = data
                    self?.balanceLabel.text = "\(data.balance)"
                    self?.updateStoreBalances(data.venueBalances)
                    self?.updateActivityUI(with: data)
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    // MARK: - Setup

    /// Manual entry for single-use brand codes (order-box cards, booth
    /// handouts). Sticker codes typed here still work — unknown codes fall
    /// back to the scan pipeline.
    private lazy var redeemCodeButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        button.setImage(UIImage(systemName: "ticket", withConfiguration: config), for: .normal)
        button.setTitle("  Have a code? Redeem it", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.tintColor = Constants.Colors.primary
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(redeemCodeTapped), for: .touchUpInside)
        return button
    }()

    @objc private func redeemCodeTapped() {
        StickerRewardCoordinator.shared.promptForCode(from: self) { [weak self] in
            self?.loadData()
        }
    }

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(headerView)
        headerView.isHidden = true
        headerView.addSubview(starImageView)
        headerView.addSubview(balanceLabel)
        headerView.addSubview(balanceCaptionLabel)
        headerView.addSubview(infoButton)

        contentView.addSubview(activeVoucherBanner)
        activeVoucherBanner.addSubview(voucherBannerTitleLabel)
        activeVoucherBanner.addSubview(voucherBannerTimeLabel)
        activeVoucherBanner.addTarget(self, action: #selector(activeVoucherBannerTapped), for: .touchUpInside)

        contentView.addSubview(redeemCodeButton)
        contentView.addSubview(storeBalancesStack)
        contentView.addSubview(ticketsStack)
        contentView.addSubview(savedOffersLabel)
        contentView.addSubview(savedOffersStack)
        contentView.addSubview(nearbyOffersLabel)
        contentView.addSubview(nearbyOffersStack)
        contentView.addSubview(howItWorksLabel)
        contentView.addSubview(stepsLabel)
        contentView.addSubview(activityLabel)
        contentView.addSubview(activityStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor),
            // No account-wide total (Wes, 2026-11-02: each store sets its own
            // rewards, so a sum of every store's points means nothing)
            headerView.heightAnchor.constraint(equalToConstant: 0),

            starImageView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            starImageView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20),
            starImageView.widthAnchor.constraint(equalToConstant: 48),
            starImageView.heightAnchor.constraint(equalToConstant: 48),

            infoButton.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            infoButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),

            balanceLabel.topAnchor.constraint(equalTo: starImageView.bottomAnchor, constant: 6),
            balanceLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),

            balanceCaptionLabel.topAnchor.constraint(equalTo: balanceLabel.bottomAnchor, constant: 2),
            balanceCaptionLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),

            activeVoucherBanner.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            activeVoucherBanner.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            activeVoucherBanner.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            voucherBannerTitleLabel.leadingAnchor.constraint(equalTo: activeVoucherBanner.leadingAnchor, constant: 14),
            voucherBannerTitleLabel.centerYAnchor.constraint(equalTo: activeVoucherBanner.centerYAnchor),
            voucherBannerTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: voucherBannerTimeLabel.leadingAnchor, constant: -10),

            voucherBannerTimeLabel.trailingAnchor.constraint(equalTo: activeVoucherBanner.trailingAnchor, constant: -14),
            voucherBannerTimeLabel.centerYAnchor.constraint(equalTo: activeVoucherBanner.centerYAnchor),

            redeemCodeButton.topAnchor.constraint(equalTo: storeBalancesStack.bottomAnchor, constant: 16),
            redeemCodeButton.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            redeemCodeButton.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            redeemCodeButton.heightAnchor.constraint(equalToConstant: 44),

            storeBalancesStack.topAnchor.constraint(equalTo: activeVoucherBanner.bottomAnchor, constant: 4),
            storeBalancesStack.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            storeBalancesStack.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            ticketsStack.topAnchor.constraint(equalTo: redeemCodeButton.bottomAnchor, constant: 20),
            ticketsStack.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            ticketsStack.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            savedOffersLabel.topAnchor.constraint(equalTo: ticketsStack.bottomAnchor, constant: 16),
            savedOffersLabel.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            savedOffersLabel.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            savedOffersStack.topAnchor.constraint(equalTo: savedOffersLabel.bottomAnchor, constant: 10),
            savedOffersStack.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            savedOffersStack.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            nearbyOffersLabel.topAnchor.constraint(equalTo: savedOffersStack.bottomAnchor, constant: 28),
            nearbyOffersLabel.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            nearbyOffersLabel.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            nearbyOffersStack.topAnchor.constraint(equalTo: nearbyOffersLabel.bottomAnchor, constant: 10),
            nearbyOffersStack.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            nearbyOffersStack.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            howItWorksLabel.topAnchor.constraint(equalTo: nearbyOffersStack.bottomAnchor, constant: 28),
            howItWorksLabel.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            howItWorksLabel.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            stepsLabel.topAnchor.constraint(equalTo: howItWorksLabel.bottomAnchor, constant: 10),
            stepsLabel.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stepsLabel.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            activityLabel.topAnchor.constraint(equalTo: stepsLabel.bottomAnchor, constant: 28),
            activityLabel.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            activityLabel.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            activityStack.topAnchor.constraint(equalTo: activityLabel.bottomAnchor, constant: 10),
            activityStack.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            activityStack.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            activityStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -30)
        ])

        // Collapsed by default; expands when a live voucher exists
        voucherBannerHeight = activeVoucherBanner.heightAnchor.constraint(equalToConstant: 0)
        voucherBannerHeight?.isActive = true
    }

    // MARK: - Per-store balances

    /// The spendable truth under the display total: one row per shop where
    /// the user holds points. Fed by both the offers and balance payloads
    /// (same data; whichever lands last wins).
    private var latestVenueBalances: [RewardVenueBalance] = []

    /// Spendable points at one shop — offer affordability is gated on this,
    /// never on the account-wide total.
    private func venuePoints(at venueId: String) -> Int {
        latestVenueBalances.first(where: { $0.venueId == venueId })?.points ?? 0
    }

    /// Which store's page each store row opens
    private var storeRowPlaceIds: [ObjectIdentifier: String] = [:]

    private func updateStoreBalances(_ balances: [RewardVenueBalance]?) {
        guard let balances = balances else { return }  // old server payload: keep what we had
        latestVenueBalances = balances
        storeBalancesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        storeRowPlaceIds.removeAll()
        guard !balances.isEmpty else { return }

        let header = UILabel()
        header.text = "Your rewards by store"
        header.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        header.textColor = .label
        storeBalancesStack.addArrangedSubview(header)
        storeBalancesStack.setCustomSpacing(12, after: header)

        // The store just earned at leads (2026-11-02)
        let ordered = balances.sorted { a, b in
            (a.venueId == highlightVenueId ? 0 : 1, -a.points) < (b.venueId == highlightVenueId ? 0 : 1, -b.points)
        }
        var highlighted: UIView?
        for balance in ordered {
            let isNew = balance.venueId == highlightVenueId
            let card = storeCard(balance, isNew: isNew)
            storeBalancesStack.addArrangedSubview(card)
            storeBalancesStack.setCustomSpacing(10, after: card)
            if isNew { highlighted = card }
        }
        if let highlighted { celebrate(highlighted) }
    }

    /// One store: its name, points here, a bar toward its next reward and
    /// what that reward is; the whole card opens the store's rewards
    private func storeCard(_ balance: RewardVenueBalance, isNew: Bool) -> UIView {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 16
        card.layer.borderWidth = isNew ? 2.5 : 0
        card.layer.borderColor = Constants.Colors.primary.cgColor

        let name = UILabel()
        name.text = balance.venueName.isEmpty ? "A shop" : balance.venueName
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        name.numberOfLines = 2
        let points = UILabel()
        points.text = "\(balance.points) pts"
        points.font = .systemFont(ofSize: 17, weight: .bold)
        points.textColor = Constants.Colors.primary
        points.setContentHuggingPriority(.required, for: .horizontal)
        points.setContentCompressionResistancePriority(.required, for: .horizontal)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let top = UIStackView(arrangedSubviews: [name, points])
        top.spacing = 8
        top.alignment = .firstBaseline

        let stack = UIStackView(arrangedSubviews: [top])
        stack.axis = .vertical
        stack.spacing = 8

        if isNew, let earned = justEarnedPoints, earned > 0 {
            let badge = UILabel()
            badge.text = "  +\(earned) just now  "
            badge.font = .systemFont(ofSize: 13, weight: .bold)
            badge.textColor = .white
            badge.backgroundColor = .systemGreen
            badge.layer.cornerRadius = 10
            badge.clipsToBounds = true
            let row = UIStackView(arrangedSubviews: [badge, UIView()])
            stack.insertArrangedSubview(row, at: 0)
        }

        if let next = balance.nextReward {
            let bar = UIProgressView(progressViewStyle: .bar)
            bar.progressTintColor = next.canRedeem ? .systemGreen : Constants.Colors.primary
            bar.trackTintColor = Constants.Colors.tertiaryBackground
            bar.progress = next.fraction
            bar.layer.cornerRadius = 4
            bar.clipsToBounds = true
            bar.heightAnchor.constraint(equalToConstant: 8).isActive = true
            let line = UILabel()
            line.text = next.canRedeem
                ? "Ready: \(next.title). Tap to redeem it at the counter."
                : RewardsAvailability.nextRewardLine(next)
            line.font = .systemFont(ofSize: 14)
            line.textColor = next.canRedeem ? .systemGreen : .secondaryLabel
            line.numberOfLines = 0
            stack.addArrangedSubview(bar)
            stack.addArrangedSubview(line)
        }

        let actions = UIStackView()
        actions.spacing = 12
        let open = UILabel()
        open.text = "See rewards here"
        open.font = .systemFont(ofSize: 14, weight: .semibold)
        open.textColor = Constants.Colors.primary
        actions.addArrangedSubview(open)
        actions.addArrangedSubview(UIView())
        // This store's card in Apple Wallet (2026-11-01)
        if WalletCardPresenter.isAvailable {
            let wallet = UIButton.iconButton(systemName: "wallet.pass")
            wallet.accessibilityLabel = "Add \(balance.venueName) to Apple Wallet"
            wallet.setContentHuggingPriority(.required, for: .horizontal)
            let venueId = balance.venueId
            wallet.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                WalletCardPresenter.present(venueId: venueId, from: self)
            }, for: .touchUpInside)
            actions.addArrangedSubview(wallet)
        }
        actions.addArrangedSubview(chevron)
        stack.addArrangedSubview(actions)

        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])

        // Tap the store: its page, at its rewards (2026-11-01)
        if let placeId = balance.globalPlaceId {
            card.isUserInteractionEnabled = true
            card.accessibilityTraits.insert(.button)
            card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(storeRowTapped(_:))))
            storeRowPlaceIds[ObjectIdentifier(card)] = placeId
        } else {
            open.isHidden = true
            chevron.isHidden = true
        }
        return card
    }

    /// The store just earned at: a quick pulse so the eye lands on it
    private func celebrate(_ card: UIView) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            UIView.animate(withDuration: 0.22, animations: { card.transform = CGAffineTransform(scaleX: 1.03, y: 1.03) }) { _ in
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) { card.transform = .identity }
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @objc private func storeRowTapped(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view, let placeId = storeRowPlaceIds[ObjectIdentifier(row)] else { return }
        let loading = AlertPresenter.showLoading(from: self)
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let place):
                        let page = PlaceDetailViewController(place: place)
                        page.scrollsToStoreRewards = true
                        self.navigationController?.pushViewController(page, animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    // MARK: - Active voucher banner

    private func updateActiveVoucherBanner() {
        voucherBannerTimer?.invalidate()
        voucherBannerTimer = nil

        guard let voucher = RewardsService.shared.getActiveVoucher() else {
            activeVoucherBanner.isHidden = true
            voucherBannerHeight?.constant = 0
            return
        }

        voucherBannerTitleLabel.text = "🎟 Your \(voucher.offerTitle) is ready, tap to show staff"
        activeVoucherBanner.isHidden = false
        voucherBannerHeight?.constant = 52
        updateVoucherBannerTime()
        voucherBannerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateVoucherBannerTime()
        }
    }

    private func updateVoucherBannerTime() {
        guard let expiry = RewardsService.shared.getActiveVoucher()?.expiryDate else {
            // Expired since the last tick — collapse the banner
            updateActiveVoucherBanner()
            return
        }
        let remaining = max(0, Int(expiry.timeIntervalSinceNow))
        voucherBannerTimeLabel.text = String(format: "%d:%02d ▸", remaining / 60, remaining % 60)
    }

    @objc private func rewardsInfoTapped() {
        AlertPresenter.showInfo(
            title: "How store points work",
            message: """
            Store points are loyalty points from the shops themselves, the ones running FavCircles Rewards. The shops fund the rewards; points are their way of saying thanks for coming in.

            ⭐ Earn them by scanning the FavCircles QR code at the register when you buy something. Each shop sets its own points, and some give extra when you save the shop to your map. Shops can also hand out single-use codes in orders or at events.

            🎁 Spend them on the offers shops post here — redeeming creates a short-lived voucher you show at the counter. Points are true loyalty: they stay with the shop where you earned them, and each shop runs its own rewards.

            Store points are separate from the FavCoins in your Piggy Bank: points are shop loyalty you spend on offers; FavCoin is a crypto coin you earn for building FavCircles and can send to your own 🌵 wallet on the blockchain — it isn't spent in the app.
            """,
            from: self,
            actionTitle: "FavCoins vs Store Points",
            action: { [weak self] in
                guard let topic = HelpContentProvider.shared.topic(withId: "favcoin-vs-store-points") else { return }
                self?.navigationController?.pushViewController(HelpTopicViewController(topic: topic), animated: true)
            }
        )
    }

    @objc private func activeVoucherBannerTapped() {
        guard let voucher = RewardsService.shared.getActiveVoucher() else {
            updateActiveVoucherBanner()
            return
        }
        let voucherVC = VoucherViewController(voucher: voucher)
        voucherVC.modalPresentationStyle = .fullScreen
        present(voucherVC, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateActiveVoucherBanner()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        voucherBannerTimer?.invalidate()
        voucherBannerTimer = nil
    }

    // MARK: - UI Updates

    private func updateOffersUI(with data: RewardOffersData?) {
        #if DEBUG
        // PREVIEW_SCREEN=rewards: sample stores, to see the cards on any account
        if ProcessInfo.processInfo.environment["PREVIEW_SCREEN"] == "rewards",
           let sample = Self.previewOffers, data?.venues.isEmpty != false {
            latestVenueBalances = sample.venueBalances ?? []
            if let y = ProcessInfo.processInfo.environment["PREVIEW_SCROLL"].flatMap(Double.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
                }
            }
            return updateOffersUI(with: sample)
        }
        #endif
        savedOffersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        nearbyOffersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let venues = data?.venues ?? []
        let saved = venues.filter { $0.savedByUser == true }
        let nearby = venues.filter { $0.savedByUser != true }

        if saved.isEmpty {
            savedOffersStack.addArrangedSubview(makeOffersEmptyCard(
                symbol: "gift",
                text: "Save a store with a FavCircles sticker and its offers show up here.",
                step: nearby.isEmpty ? .explore : nil))
        } else {
            saved.forEach { savedOffersStack.addArrangedSubview(makeVenueCard($0)) }
        }

        if nearby.isEmpty {
            nearbyOffersStack.addArrangedSubview(makeOffersEmptyCard(
                symbol: "mappin.and.ellipse",
                text: "No stores with rewards near you yet. Look for the FavCircles sticker in shop windows.",
                step: .explore))
        } else {
            nearbyOffersStack.addArrangedSubview(makeNearbyCarousel(nearby))
        }
    }

    private func updateActivityUI(with data: RewardBalanceData) {
        activityStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if data.events.isEmpty {
            activityStack.addArrangedSubview(makeEmptyLabel(
                "No store rewards yet. Scan a store's FavCircles QR code to get started!"
            ))
            return
        }

        for event in data.events {
            activityStack.addArrangedSubview(makeEventRow(event))
        }
    }

    private func makeEmptyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    // MARK: - Venue offer cards (2026-11-03: photo cards like Store Rewards)

    /// A store's photo, or its category's icon on the brand color while
    /// there's none (and while the photo loads)
    private func makeVenuePhoto(_ venue: OfferVenue, height: CGFloat) -> UIView {
        let header = UIView()
        header.backgroundColor = Constants.Colors.primary
        header.clipsToBounds = true
        header.heightAnchor.constraint(equalToConstant: height).isActive = true

        let category = PlaceCategory(rawValue: venue.category ?? "")
        let icon = UIImageView(image: UIImage(systemName: category?.systemIconName ?? "storefront"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.85)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(icon)

        let photo = UIImageView()
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(photo)
        if let url = venue.photoUrl, !url.isEmpty {
            ImageService.shared.loadImage(from: url) { image in
                DispatchQueue.main.async {
                    guard let image else { return }
                    photo.image = image
                    icon.isHidden = true
                }
            }
        }

        // Distance (or "Online store") in a chip over the photo
        let chipText = venue.isVirtual == true ? "Online store" : venue.distanceDisplay
        if let chipText {
            let chip = PaddedChip(text: chipText)
            chip.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(chip)
            NSLayoutConstraint.activate([
                chip.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
                chip.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10)
            ])
        }

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            icon.heightAnchor.constraint(equalToConstant: height * 0.36),
            icon.widthAnchor.constraint(equalTo: icon.heightAnchor),
            photo.topAnchor.constraint(equalTo: header.topAnchor),
            photo.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            photo.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            photo.trailingAnchor.constraint(equalTo: header.trailingAnchor)
        ])
        if let chip = header.subviews.first(where: { $0 is PaddedChip }) { header.bringSubviewToFront(chip) }
        return header
    }

    /// The reward this person is working toward at a store, on the same rule
    /// as the place page and Store Rewards
    private func nextReward(at venue: OfferVenue) -> RewardsAvailability.NextReward? {
        RewardsAvailability.nextReward(RewardsAvailability.Details(
            venueName: venue.venueName,
            earnRate: venue.earnRate,
            venueBalance: venuePoints(at: venue.venueId),
            offers: venue.offers.filter { $0.active != false }.map { .init(title: $0.title, pointsCost: $0.pointsCost) }))
    }

    /// A saved store: photo, name, points here, progress to the next
    /// reward, then each offer with Redeem or how far away it is
    private func makeVenueCard(_ venue: OfferVenue) -> UIView {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 16
        card.clipsToBounds = true

        let photo = makeVenuePhoto(venue, height: 128)

        let name = UILabel()
        name.text = venue.venueName
        name.font = .systemFont(ofSize: 18, weight: .bold)
        name.numberOfLines = 2
        let pointsHere = venuePoints(at: venue.venueId)
        let points = UILabel()
        points.text = "\(pointsHere) pts"
        points.font = .systemFont(ofSize: 17, weight: .bold)
        points.textColor = pointsHere > 0 ? Constants.Colors.primary : .tertiaryLabel
        points.setContentHuggingPriority(.required, for: .horizontal)
        points.setContentCompressionResistancePriority(.required, for: .horizontal)
        let titleRow = UIStackView(arrangedSubviews: [name, points])
        titleRow.spacing = 8
        titleRow.alignment = .firstBaseline

        let body = UIStackView(arrangedSubviews: [titleRow])
        body.axis = .vertical
        body.spacing = 10

        if let rate = venue.earnRate, rate > 0 {
            body.addArrangedSubview(makeIconLine(symbol: "star.circle.fill", color: .systemOrange,
                                                 text: "Earn \(rate) \(rate == 1 ? "point" : "points") per purchase"))
        }

        if let next = nextReward(at: venue) {
            let bar = UIProgressView(progressViewStyle: .bar)
            bar.progressTintColor = next.canRedeem ? .systemGreen : Constants.Colors.primary
            bar.trackTintColor = Constants.Colors.tertiaryBackground
            bar.progress = next.fraction
            bar.layer.cornerRadius = 4
            bar.clipsToBounds = true
            bar.heightAnchor.constraint(equalToConstant: 8).isActive = true
            let line = UILabel()
            line.text = RewardsAvailability.nextRewardLine(next)
            line.font = .systemFont(ofSize: 14)
            line.textColor = next.canRedeem ? .systemGreen : .secondaryLabel
            line.numberOfLines = 0
            body.addArrangedSubview(bar)
            body.addArrangedSubview(line)
        }

        let offers = venue.offers.filter { $0.active != false }.sorted { $0.pointsCost < $1.pointsCost }
        if !offers.isEmpty {
            let divider = UIView()
            divider.backgroundColor = .separator
            divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            body.addArrangedSubview(divider)
            offers.forEach { body.addArrangedSubview(makeOfferRow($0, venue: venue)) }
        }

        let open = UILabel()
        open.text = "See the store"
        open.font = .systemFont(ofSize: 14, weight: .semibold)
        open.textColor = Constants.Colors.primary
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        body.addArrangedSubview(UIStackView(arrangedSubviews: [open, UIView(), chevron]))

        let column = UIStackView(arrangedSubviews: [photo, body])
        column.axis = .vertical
        column.spacing = 12
        column.setCustomSpacing(14, after: photo)
        column.translatesAutoresizingMaskIntoConstraints = false
        body.isLayoutMarginsRelativeArrangement = true
        body.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 14, trailing: 16)
        card.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: card.topAnchor),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        // Tap anywhere but Redeem: the store's page
        card.accessibilityTraits.insert(.button)
        card.addGestureRecognizer(VenueTap(venue: venue, target: self, action: #selector(venueCardTapped(_:))))
        return card
    }

    /// Stores near you that you haven't saved: a swipeable row of photo cards
    private func makeNearbyCarousel(_ venues: [OfferVenue]) -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.clipsToBounds = false
        let row = UIStackView(arrangedSubviews: venues.map { makeNearbyCard($0) })
        row.spacing = 12
        row.alignment = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        scroll.heightAnchor.constraint(equalToConstant: 236).isActive = true
        return scroll
    }

    private func makeNearbyCard(_ venue: OfferVenue) -> UIView {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        card.widthAnchor.constraint(equalToConstant: 236).isActive = true

        let photo = makeVenuePhoto(venue, height: 112)
        let name = UILabel()
        name.text = venue.venueName
        name.font = .systemFont(ofSize: 16, weight: .bold)
        name.numberOfLines = 1

        let body = UIStackView(arrangedSubviews: [name])
        body.axis = .vertical
        body.spacing = 6
        body.isLayoutMarginsRelativeArrangement = true
        body.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12)

        let offers = venue.offers.filter { $0.active != false }.sorted { $0.pointsCost < $1.pointsCost }
        if let first = offers.first {
            let more = offers.count > 1 ? " + \(offers.count - 1) more" : ""
            body.addArrangedSubview(makeIconLine(symbol: "gift.fill", color: Constants.Colors.primary,
                                                 text: "\(first.title) · \(first.pointsCost) pts\(more)", lines: 2))
        }
        if let rate = venue.earnRate, rate > 0 {
            body.addArrangedSubview(makeIconLine(symbol: "star.circle.fill", color: .systemOrange,
                                                 text: "\(rate) pts per purchase"))
        }
        body.addArrangedSubview(UIView())

        let column = UIStackView(arrangedSubviews: [photo, body])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: card.topAnchor),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])
        card.accessibilityTraits.insert(.button)
        card.addGestureRecognizer(VenueTap(venue: venue, target: self, action: #selector(venueCardTapped(_:))))
        return card
    }

    /// An SF Symbol and a line of text, for the earn rate and offer lines
    private func makeIconLine(symbol: String, color: UIColor, text: String, lines: Int = 1) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = color
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = lines
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 6
        row.alignment = .center
        return row
    }

    /// No stores yet: a soft card that says why, with a way forward
    private func makeOffersEmptyCard(symbol: String, text: String, step: NextStep?) -> UIView {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 16
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let label = makeEmptyLabel(text)
        label.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        if let step {
            let button = UIButton.smallActionButton(title: step.title, style: .primary)
            button.addAction(UIAction { _ in
                AnalyticsService.shared.logEvent("next_step_tapped", parameters: ["surface": "rewards_offers_empty", "step": step.id])
                NextStepNavigator.explore()
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20)
        ])
        return card
    }

    @objc private func venueCardTapped(_ gesture: VenueTap) {
        openVenuePlace(gesture.venue)
    }

    // MARK: - Venue → place page

    /// Opens the place page for a venue card. Resolves the canonical global
    /// place when an id is available; otherwise falls back to a minimal Place
    /// built from the venue's own fields (PlaceDetail refreshes what it can).
    private func openVenuePlace(_ venue: OfferVenue) {
        guard let placeId = venue.globalPlaceId ?? venue.googlePlaceId else {
            pushVenuePlaceFallback(venue)
            return
        }

        let loading = AlertPresenter.showLoading(message: "Loading place...", from: self)
        GlobalPlaceService.shared.getGlobalPlace(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let response):
                        let place = response.bestDetailPlace()
                        let detailVC = PlaceDetailViewController(place: place)
                        self.navigationController?.pushViewController(detailVC, animated: true)
                    case .failure:
                        self.pushVenuePlaceFallback(venue)
                    }
                }
            }
        }
    }

    private func pushVenuePlaceFallback(_ venue: OfferVenue) {
        var location: GeoLocation?
        if let coordinate = venue.location {
            // GeoJSON order: [longitude, latitude]
            location = GeoLocation(type: "Point", coordinates: [coordinate.lng, coordinate.lat])
        }

        let place = Place(
            id: venue.globalPlaceId ?? venue.googlePlaceId ?? venue.venueId,
            globalPlaceId: venue.globalPlaceId,
            name: venue.placeName ?? venue.venueName,
            description: nil,
            address: venue.placeAddress ?? "",
            location: location,
            website: nil,
            phone: nil,
            googlePlaceId: venue.googlePlaceId,
            photos: nil,
            videos: nil,
            category: PlaceCategory(rawValue: venue.category ?? "") ?? .restaurant,
            customCategoryId: nil,
            subcategory: nil,
            rating: nil,
            userRatingsTotal: nil,
            notes: nil,
            privateNotes: nil,
            publicNotes: nil,
            tags: nil,
            reviews: nil,
            openingHours: nil,
            priceLevel: nil,
            likes: nil,
            likesCount: nil,
            commentsCount: nil,
            circleId: nil,
            addedBy: "",
            addedByUser: nil,
            privacy: .public,
            createdAt: Date(),
            updatedAt: Date()
        )
        let detailVC = PlaceDetailViewController(place: place)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    /// One offer: a gift badge, the title and cost, then Redeem when this
    /// store's points cover it, or how many more points it takes
    private func makeOfferRow(_ offer: RewardOffer, venue: OfferVenue) -> UIView {
        // Per-store loyalty: only points earned at THIS shop pay for its offers
        let balance = venuePoints(at: venue.venueId)
        let affordable = balance >= offer.pointsCost

        let badge = UIView()
        badge.backgroundColor = (affordable ? UIColor.systemGreen : Constants.Colors.primary).withAlphaComponent(0.14)
        badge.layer.cornerRadius = 18
        badge.widthAnchor.constraint(equalToConstant: 36).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let gift = UIImageView(image: UIImage(systemName: "gift.fill"))
        gift.tintColor = affordable ? .systemGreen : Constants.Colors.primary
        gift.contentMode = .scaleAspectFit
        gift.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(gift)
        NSLayoutConstraint.activate([
            gift.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            gift.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            gift.widthAnchor.constraint(equalToConstant: 18),
            gift.heightAnchor.constraint(equalToConstant: 18)
        ])

        let title = UILabel()
        title.text = offer.title
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.numberOfLines = 2
        let cost = UILabel()
        cost.text = "\(offer.pointsCost) pts"
        cost.font = .systemFont(ofSize: 13)
        cost.textColor = .secondaryLabel
        let text = UIStackView(arrangedSubviews: [title, cost])
        text.axis = .vertical
        text.spacing = 2

        let trailing: UIView
        if affordable {
            let redeem = UIButton.smallActionButton(title: "Redeem", style: .primary)
            redeem.addAction(UIAction { [weak self] _ in
                self?.confirmRedeem(offer, venue: venue)
            }, for: .touchUpInside)
            trailing = redeem
        } else {
            trailing = PaddedChip(text: "\(offer.pointsCost - balance) to go", muted: true)
        }
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [badge, text, trailing])
        row.spacing = 12
        row.alignment = .center
        return row
    }

    // MARK: - Redemption

    private func confirmRedeem(_ offer: RewardOffer, venue: OfferVenue) {
        confirmAndRedeemOffer(offer, venueId: venue.venueId, venueName: venue.venueName) { [weak self] _ in
            // Refresh balance, affordability, history, and the
            // active-voucher banner behind the voucher screen
            self?.loadData()
            self?.updateActiveVoucherBanner()
        }
    }

    // MARK: - Activity rows

    private func makeEventRow(_ event: RewardEventItem) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = event.displayTitle
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        let pointsLabel = UILabel()
        pointsLabel.translatesAutoresizingMaskIntoConstraints = false
        pointsLabel.text = event.points >= 0 ? "+\(event.points)" : "\(event.points)"
        pointsLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        pointsLabel.textColor = event.points >= 0 ? .systemGreen : .systemRed
        pointsLabel.setContentHuggingPriority(.required, for: .horizontal)
        pointsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator

        row.addSubview(titleLabel)
        row.addSubview(pointsLabel)
        row.addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -12),

            pointsLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            pointsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            pointsLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),

            separator.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        return row
    }
}

// MARK: - CLLocationManagerDelegate

extension RewardsViewController: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Only react while the initial offers load is pending — this callback
        // also fires when the delegate is first set
        guard offersData == nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            fetchOffers(lat: nil, lng: nil)
        case .notDetermined:
            break
        @unknown default:
            fetchOffers(lat: nil, lng: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.first?.coordinate
        fetchOffers(lat: coordinate?.latitude, lng: coordinate?.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No fix — load offers without distance sorting
        fetchOffers(lat: nil, lng: nil)
    }
}

/// A tap that knows which store's card it's on
private final class VenueTap: UITapGestureRecognizer {
    let venue: OfferVenue
    init(venue: OfferVenue, target: Any?, action: Selector?) {
        self.venue = venue
        super.init(target: target, action: action)
        cancelsTouchesInView = false
    }
}

/// A small rounded label: the distance over a store photo, or "40 to go"
private final class PaddedChip: UILabel {
    init(text: String, muted: Bool = false) {
        super.init(frame: .zero)
        self.text = text
        font = .systemFont(ofSize: 12, weight: .semibold)
        textColor = muted ? .secondaryLabel : .white
        backgroundColor = muted ? Constants.Colors.tertiaryBackground : UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 11
        clipsToBounds = true
        textAlignment = .center
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 18, height: max(22, size.height + 6))
    }
}

#if DEBUG
extension RewardsViewController {
    static let previewOffers: RewardOffersData? = {
        let json = """
        {"balance": 0,
         "venueBalances": [{"venueId": "sal", "venueName": "Sal’s Bakery (Demo)", "points": 75}],
         "venues": [
          {"venueId": "sal", "venueName": "Sal’s Bakery (Demo)", "category": "bakery", "savedByUser": true,
           "photoUrl": "https://images.unsplash.com/photo-1509440159596-0249088772ff?w=1200", "distanceMeters": 640, "earnRate": 25,
           "offers": [{"offerId": "1", "title": "Free drip coffee", "pointsCost": 50},
                      {"offerId": "2", "title": "Free croissant", "pointsCost": 100},
                      {"offerId": "3", "title": "Dozen cookies", "pointsCost": 300}]},
          {"venueId": "tb", "venueName": "Test Bakery", "category": "cafe", "savedByUser": true, "distanceMeters": 3200, "earnRate": 10,
           "offers": [{"offerId": "4", "title": "10% off your order", "pointsCost": 80}]},
          {"venueId": "n1", "venueName": "Undercurrent Coffee", "category": "cafe", "savedByUser": false,
           "photoUrl": "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=1200", "distanceMeters": 1100, "earnRate": 10,
           "offers": [{"offerId": "5", "title": "Free latte", "pointsCost": 120}, {"offerId": "6", "title": "Free pastry", "pointsCost": 60}]},
          {"venueId": "n2", "venueName": "Pasta & Provisions", "category": "restaurant", "savedByUser": false,
           "photoUrl": "https://images.unsplash.com/photo-1473093295043-cdd812d0e601?w=1200", "distanceMeters": 4200, "earnRate": 20,
           "offers": [{"offerId": "7", "title": "Free garlic bread", "pointsCost": 100}]}
         ]}
        """
        return try? JSONDecoder().decode(RewardOffersData.self, from: Data(json.utf8))
    }()
}
#endif
