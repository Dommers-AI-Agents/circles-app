import UIKit
import CoreLocation

/// Rewards home: points balance, browsable offers from participating places
/// (saved places first, then nearby), how the program works, and recent
/// activity. Entry points: the $ button on the home screen and the star
/// button on the Profile screen.
class RewardsViewController: BaseViewController {

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
        label.text = "store points → get rewards"
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
        📲 Scan it and save the place to a circle (+50 pts)
        🧾 Scan the register card when you buy something — each shop sets its own points
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
        let alert = UIAlertController(
            title: "Redeem a Code",
            message: "Enter the code from your order card or booth handout",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "CODE"
            field.autocapitalizationType = .allCharacters
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Redeem", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let code = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                  !code.isEmpty else { return }
            self.submitRedemptionCode(code)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func submitRedemptionCode(_ code: String) {
        RewardsService.shared.redeemCode(code) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let data):
                    if let awarded = data.awarded {
                        let store = awarded.venueName ?? "the store"
                        self.showSuccess("+\(awarded.points) points from \(store)!")
                    } else {
                        self.showSuccess("Code accepted")
                    }
                    self.loadData()
                case .failure(let error):
                    // Not a brand code? It may be a sticker code — same entry
                    // point works for both
                    let message = (error as? APIError)?.serverMessage ?? error.localizedDescription
                    if message.localizedCaseInsensitiveContains("not found") {
                        StickerRewardCoordinator.shared.handleScannedCode(code)
                    } else {
                        self.showError(message)
                    }
                }
            }
        }
    }

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(headerView)
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
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 190),

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
            activeVoucherBanner.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            activeVoucherBanner.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            voucherBannerTitleLabel.leadingAnchor.constraint(equalTo: activeVoucherBanner.leadingAnchor, constant: 14),
            voucherBannerTitleLabel.centerYAnchor.constraint(equalTo: activeVoucherBanner.centerYAnchor),
            voucherBannerTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: voucherBannerTimeLabel.leadingAnchor, constant: -10),

            voucherBannerTimeLabel.trailingAnchor.constraint(equalTo: activeVoucherBanner.trailingAnchor, constant: -14),
            voucherBannerTimeLabel.centerYAnchor.constraint(equalTo: activeVoucherBanner.centerYAnchor),

            redeemCodeButton.topAnchor.constraint(equalTo: activeVoucherBanner.bottomAnchor, constant: 12),
            redeemCodeButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            redeemCodeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            redeemCodeButton.heightAnchor.constraint(equalToConstant: 44),

            storeBalancesStack.topAnchor.constraint(equalTo: redeemCodeButton.bottomAnchor, constant: 16),
            storeBalancesStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            storeBalancesStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            savedOffersLabel.topAnchor.constraint(equalTo: storeBalancesStack.bottomAnchor, constant: 16),
            savedOffersLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            savedOffersLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            savedOffersStack.topAnchor.constraint(equalTo: savedOffersLabel.bottomAnchor, constant: 10),
            savedOffersStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            savedOffersStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            nearbyOffersLabel.topAnchor.constraint(equalTo: savedOffersStack.bottomAnchor, constant: 28),
            nearbyOffersLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nearbyOffersLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            nearbyOffersStack.topAnchor.constraint(equalTo: nearbyOffersLabel.bottomAnchor, constant: 10),
            nearbyOffersStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nearbyOffersStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            howItWorksLabel.topAnchor.constraint(equalTo: nearbyOffersStack.bottomAnchor, constant: 28),
            howItWorksLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            howItWorksLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            stepsLabel.topAnchor.constraint(equalTo: howItWorksLabel.bottomAnchor, constant: 10),
            stepsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stepsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            activityLabel.topAnchor.constraint(equalTo: stepsLabel.bottomAnchor, constant: 28),
            activityLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            activityLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            activityStack.topAnchor.constraint(equalTo: activityLabel.bottomAnchor, constant: 10),
            activityStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            activityStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
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

    private func updateStoreBalances(_ balances: [RewardVenueBalance]?) {
        guard let balances = balances else { return }  // old server payload: keep what we had
        latestVenueBalances = balances
        storeBalancesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !balances.isEmpty else { return }

        let header = UILabel()
        header.text = "Your points by store"
        header.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        header.textColor = .label
        storeBalancesStack.addArrangedSubview(header)
        storeBalancesStack.setCustomSpacing(10, after: header)

        for balance in balances {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8

            let name = UILabel()
            name.text = "🏬 \(balance.venueName.isEmpty ? "A shop" : balance.venueName)"
            name.font = UIFont.systemFont(ofSize: 14)
            name.textColor = .label
            name.numberOfLines = 1

            let points = UILabel()
            points.text = "\(balance.points) pts"
            points.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            points.textColor = Constants.Colors.primary
            points.textAlignment = .right
            points.setContentHuggingPriority(.required, for: .horizontal)
            points.setContentCompressionResistancePriority(.required, for: .horizontal)

            row.addArrangedSubview(name)
            row.addArrangedSubview(points)
            storeBalancesStack.addArrangedSubview(row)
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

        voucherBannerTitleLabel.text = "🎟 Active voucher — \(voucher.offerTitle)"
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
            Store points are loyalty points from the shops themselves — the places with a FavCircles sticker in the window. The shops fund the rewards; points are their way of saying thanks for coming in.

            ⭐ Earn them by scanning a window sticker and saving the place (+50), scanning the register card when you buy something (each shop sets its own points), and redeeming the single-use codes shops pack into orders or hand out at events.

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
        savedOffersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        nearbyOffersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let venues = data?.venues ?? []
        let saved = venues.filter { $0.savedByUser == true }
        let nearby = venues.filter { $0.savedByUser != true }

        if saved.isEmpty {
            savedOffersStack.addArrangedSubview(makeEmptyLabel(
                "Save places with a FavCircles sticker to see their offers here."
            ))
        } else {
            saved.forEach { savedOffersStack.addArrangedSubview(makeVenueCard($0)) }
        }

        if nearby.isEmpty {
            nearbyOffersStack.addArrangedSubview(makeEmptyLabel(
                "No participating places nearby yet — keep an eye out for FavCircles stickers!"
            ))
        } else {
            nearby.forEach { nearbyOffersStack.addArrangedSubview(makeVenueCard($0)) }
        }
    }

    private func updateActivityUI(with data: RewardBalanceData) {
        activityStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if data.events.isEmpty {
            activityStack.addArrangedSubview(makeEmptyLabel(
                "No store points yet — scan a FavCircles sticker to get started!"
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

    // MARK: - Venue offer cards

    private func makeVenueCard(_ venue: OfferVenue) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = venue.venueName
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 1

        let detailLabel = UILabel()
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        var details: [String] = []
        if let distance = venue.distanceDisplay { details.append(distance) }
        if let earnRate = venue.earnRate { details.append("earn \(earnRate) pts per purchase") }
        let pointsHere = venuePoints(at: venue.venueId)
        if pointsHere > 0 { details.append("you have \(pointsHere) pts here") }
        detailLabel.text = details.joined(separator: " · ")
        detailLabel.font = UIFont.systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 1

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        // The name/detail header opens the venue's place page; the redeem
        // buttons below keep their own tap targets.
        let headerControl = UIControl()
        headerControl.translatesAutoresizingMaskIntoConstraints = false
        headerControl.addAction(UIAction { [weak self] _ in
            self?.openVenuePlace(venue)
        }, for: .touchUpInside)
        headerControl.addSubview(nameLabel)
        headerControl.addSubview(detailLabel)
        headerControl.addSubview(chevron)
        nameLabel.isUserInteractionEnabled = false
        detailLabel.isUserInteractionEnabled = false
        chevron.isUserInteractionEnabled = false

        let offersStack = UIStackView()
        offersStack.translatesAutoresizingMaskIntoConstraints = false
        offersStack.axis = .vertical
        offersStack.spacing = 8
        venue.offers.forEach { offersStack.addArrangedSubview(makeOfferRow($0, venue: venue)) }

        card.addSubview(headerControl)
        card.addSubview(offersStack)

        NSLayoutConstraint.activate([
            headerControl.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            headerControl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            headerControl.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            nameLabel.topAnchor.constraint(equalTo: headerControl.topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: headerControl.leadingAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            chevron.centerYAnchor.constraint(equalTo: headerControl.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: headerControl.trailingAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),

            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
            detailLabel.bottomAnchor.constraint(equalTo: headerControl.bottomAnchor),

            offersStack.topAnchor.constraint(equalTo: headerControl.bottomAnchor, constant: 10),
            offersStack.leadingAnchor.constraint(equalTo: headerControl.leadingAnchor),
            offersStack.trailingAnchor.constraint(equalTo: headerControl.trailingAnchor),
            offersStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
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

    private func makeOfferRow(_ offer: RewardOffer, venue: OfferVenue) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        // Per-store loyalty: only points earned at THIS shop pay for its offers
        let balance = venuePoints(at: venue.venueId)
        let affordable = balance >= offer.pointsCost

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = offer.title
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        let costLabel = UILabel()
        costLabel.translatesAutoresizingMaskIntoConstraints = false
        costLabel.text = affordable
            ? "\(offer.pointsCost) pts"
            : "\(offer.pointsCost) pts · earn \(offer.pointsCost - balance) more here"
        costLabel.font = UIFont.systemFont(ofSize: 12)
        costLabel.textColor = .secondaryLabel

        let redeemButton = UIButton.smallActionButton(
            title: "Redeem",
            style: affordable ? .primary : .secondary
        )
        redeemButton.isEnabled = affordable
        redeemButton.alpha = affordable ? 1.0 : 0.5
        redeemButton.setContentHuggingPriority(.required, for: .horizontal)
        redeemButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        redeemButton.addAction(UIAction { [weak self] _ in
            self?.confirmRedeem(offer, venue: venue)
        }, for: .touchUpInside)

        row.addSubview(titleLabel)
        row.addSubview(costLabel)
        row.addSubview(redeemButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: redeemButton.leadingAnchor, constant: -10),

            costLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            costLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            costLabel.trailingAnchor.constraint(lessThanOrEqualTo: redeemButton.leadingAnchor, constant: -10),
            costLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            redeemButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            redeemButton.trailingAnchor.constraint(equalTo: row.trailingAnchor)
        ])

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
