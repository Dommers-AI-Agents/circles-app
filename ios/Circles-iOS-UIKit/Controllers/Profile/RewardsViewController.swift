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
        label.text = "reward points"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .white.withAlphaComponent(0.9)
        label.textAlignment = .center
        return label
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
        🔗 Share places with friends — earn +50 pts when they add one
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
                    self.updateOffersUI(with: data)
                case .failure(let error):
                    // Offers are additive — balance/history still render
                    print("⚠️ Failed to load offers: \(error)")
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
                    self?.updateActivityUI(with: data)
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(headerView)
        headerView.addSubview(starImageView)
        headerView.addSubview(balanceLabel)
        headerView.addSubview(balanceCaptionLabel)

        contentView.addSubview(activeVoucherBanner)
        activeVoucherBanner.addSubview(voucherBannerTitleLabel)
        activeVoucherBanner.addSubview(voucherBannerTimeLabel)
        activeVoucherBanner.addTarget(self, action: #selector(activeVoucherBannerTapped), for: .touchUpInside)

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

            savedOffersLabel.topAnchor.constraint(equalTo: activeVoucherBanner.bottomAnchor, constant: 16),
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
                "No rewards yet — scan a FavCircles sticker to get started!"
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
        detailLabel.text = details.joined(separator: " · ")
        detailLabel.font = UIFont.systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 1

        let offersStack = UIStackView()
        offersStack.translatesAutoresizingMaskIntoConstraints = false
        offersStack.axis = .vertical
        offersStack.spacing = 8
        venue.offers.forEach { offersStack.addArrangedSubview(makeOfferRow($0, venue: venue)) }

        card.addSubview(nameLabel)
        card.addSubview(detailLabel)
        card.addSubview(offersStack)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),

            offersStack.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 10),
            offersStack.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            offersStack.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            offersStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    private func makeOfferRow(_ offer: RewardOffer, venue: OfferVenue) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let balance = offersData?.balance ?? 0
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
            : "\(offer.pointsCost) pts · \(offer.pointsCost - balance) more needed"
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
        showConfirmation(
            title: "Redeem \(offer.title)?",
            message: "This uses \(offer.pointsCost) points and shows a 5-minute voucher — redeem it at the counter at \(venue.venueName)."
        ) { [weak self] in
            self?.redeem(offer, venue: venue)
        }
    }

    private func redeem(_ offer: RewardOffer, venue: OfferVenue) {
        let loading = AlertPresenter.showLoading(message: "Redeeming...", from: self)

        RewardsService.shared.redeemOffer(venueId: venue.venueId, offerId: offer.offerId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let redeem):
                        let voucherVC = VoucherViewController(voucher: redeem.voucher)
                        voucherVC.modalPresentationStyle = .fullScreen
                        self.present(voucherVC, animated: true)
                        // Refresh balance, affordability, history, and the
                        // active-voucher banner behind the voucher screen
                        self.loadData()
                        self.updateActiveVoucherBanner()
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
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
