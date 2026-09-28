import UIKit

/// "Get Rewards" for one store: how to earn here, in the order a customer
/// needs it — scan the QR code at the register, or type a code from a receipt
/// or card — then what the points buy.
///
/// Opened from the place page's Get Rewards button and from the check-in
/// confirmation. Built from the venue data the caller already has; refetches
/// only after a scan or code changes the balance.
final class GetRewardsViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let place: Place
    private var details: RewardsAvailability.Details

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.medium
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let earnLabel = GetRewardsViewController.label(size: Constants.FontSize.xlarge, weight: .bold)
    private let balanceLabel = GetRewardsViewController.label(size: Constants.FontSize.large, weight: .regular,
                                                              color: Constants.Colors.secondaryLabel)
    private let offersStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.xsmall
        return stack
    }()

    private lazy var scanButton: UIButton = {
        let button = UIButton.primaryButton(title: "Scan QR code")
        button.setImage(UIImage(systemName: "qrcode.viewfinder"), for: .normal)
        button.tintColor = .white
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -6, bottom: 0, right: 6)
        button.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
        return button
    }()

    private lazy var typeCodeButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Type a code")
        button.addTarget(self, action: #selector(typeCodeTapped), for: .touchUpInside)
        return button
    }()

    /// - Returns: nil when the data says there are no rewards to get here.
    init?(place: Place, data: PlaceVenueData?) {
        guard let details = RewardsAvailability(data).details else { return nil }
        self.place = place
        self.details = details
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Get Rewards"
        view.backgroundColor = Constants.Colors.background
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        }

        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Constants.Spacing.large),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Constants.Spacing.large),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: Constants.Spacing.medium),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -Constants.Spacing.medium)
        ])

        buildContent()
        render()

        NotificationCenter.default.addObserver(self, selector: #selector(pointsChanged),
                                               name: .rewardPointsDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Content

    private func buildContent() {
        let nameLabel = Self.label(size: Constants.FontSize.medium, weight: .semibold, color: Constants.Colors.secondaryLabel)
        nameLabel.text = details.venueName.uppercased()
        stack.addArrangedSubview(nameLabel)
        stack.setCustomSpacing(Constants.Spacing.tiny, after: nameLabel)
        stack.addArrangedSubview(earnLabel)
        stack.setCustomSpacing(Constants.Spacing.tiny, after: earnLabel)
        stack.addArrangedSubview(balanceLabel)
        stack.setCustomSpacing(Constants.Spacing.large, after: balanceLabel)

        stack.addArrangedSubview(Self.stepHeader("Scan the QR code at the register"))
        let scanCaption = Self.caption("After you buy something, scan the FavCircles QR code by the register. Ask staff if you can't find it. You can earn once a day.")
        stack.addArrangedSubview(scanCaption)
        stack.addArrangedSubview(scanButton)
        stack.setCustomSpacing(Constants.Spacing.large, after: scanButton)

        stack.addArrangedSubview(Self.stepHeader("Have a code instead?"))
        stack.addArrangedSubview(Self.caption("Codes printed on a receipt, an order card or under the store's QR code work too."))
        stack.addArrangedSubview(typeCodeButton)
        stack.setCustomSpacing(Constants.Spacing.large, after: typeCodeButton)

        stack.addArrangedSubview(offersStack)
    }

    private func render() {
        earnLabel.text = RewardsAvailability.earnLine(details) ?? "Earn points every visit"
        balanceLabel.text = RewardsAvailability.balanceLine(details)

        offersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !details.offers.isEmpty else { return }
        offersStack.addArrangedSubview(Self.stepHeader("What your points get you here"))
        for offer in details.offers.sorted(by: { $0.pointsCost < $1.pointsCost }) {
            offersStack.addArrangedSubview(offerRow(offer))
        }
    }

    private func offerRow(_ offer: RewardsAvailability.Offer) -> UIView {
        let title = Self.label(size: Constants.FontSize.large, weight: .medium)
        title.text = offer.title
        let cost = Self.label(size: Constants.FontSize.medium, weight: .semibold,
                              color: offer.pointsCost <= details.venueBalance ? Constants.Colors.primary : Constants.Colors.secondaryLabel)
        cost.text = "\(offer.pointsCost) pts"
        cost.setContentHuggingPriority(.required, for: .horizontal)
        cost.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [title, cost])
        row.spacing = Constants.Spacing.small
        row.alignment = .firstBaseline
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        row.backgroundColor = Constants.Colors.secondaryBackground
        row.layer.cornerRadius = 10
        return row
    }

    // MARK: - Refresh

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.getVenueByPlace(placeId: place.globalPlaceId ?? place.id,
                                              googlePlaceId: place.googlePlaceId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let data) = result, let details = RewardsAvailability(data).details {
                    self?.details = details
                    self?.render()
                }
                completion?()
            }
        }
    }

    @objc private func pointsChanged() {
        loadData()
    }

    // MARK: - Actions

    @objc private func scanTapped() {
        let nav = UINavigationController(rootViewController: RewardScannerViewController())
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    @objc private func typeCodeTapped() {
        StickerRewardCoordinator.shared.promptForCode(from: self)
    }

    @objc private func closeTapped() {
        (navigationController ?? self).dismiss(animated: true)
    }

    // MARK: - Factories

    private static func label(size: CGFloat, weight: UIFont.Weight, color: UIColor = Constants.Colors.label) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private static func caption(_ text: String) -> UILabel {
        let label = label(size: Constants.FontSize.medium, weight: .regular, color: Constants.Colors.secondaryLabel)
        label.text = text
        return label
    }

    private static func stepHeader(_ title: String) -> UILabel {
        let label = label(size: Constants.FontSize.large, weight: .semibold)
        label.text = title
        return label
    }
}
