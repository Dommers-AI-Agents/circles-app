import UIKit

/// Store-owner stats dashboard for one venue. Headline numbers (saves,
/// followers, visits, scans, sign-ups, redemptions) are visible to every
/// claimed owner; the monthly breakdown is a business-subscription feature —
/// free owners see a locked card instead. Reached from VenueManageViewController.
class VenueDashboardViewController: BaseViewController {

    // MARK: - Properties

    private let venueId: String
    private let venueName: String
    private var dashboard: VenueDashboardData?

    override var enablesPullToRefresh: Bool { true }

    // MARK: - UI Elements

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        return scroll
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.medium
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let statsGrid: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.medium
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let detailSection: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.small
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Init

    init(venueId: String, venueName: String) {
        self.venueId = venueId
        self.venueName = venueName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stats & Insights"
        view.backgroundColor = .systemBackground

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        contentStack.addArrangedSubview(makeHeaderLabel())
        contentStack.addArrangedSubview(statsGrid)
        contentStack.addArrangedSubview(detailSection)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Constants.Spacing.medium),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Constants.Spacing.medium),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Constants.Spacing.medium),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Constants.Spacing.large),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Constants.Spacing.medium)
        ])
    }

    override func setupRefreshControl() {
        scrollView.refreshControl = refreshControl
    }

    // MARK: - BaseViewController

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.getVenueDashboard(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self = self else { return }
                switch result {
                case .success(let dashboard):
                    self.dashboard = dashboard
                    self.render(dashboard)
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Rendering

    private func makeHeaderLabel() -> UILabel {
        let label = UILabel()
        label.text = venueName
        label.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        label.textColor = Constants.Colors.label
        return label
    }

    private func render(_ dashboard: VenueDashboardData) {
        statsGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        detailSection.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let headline = dashboard.headline
        let stats: [(String, Int)] = [
            ("Saved by", headline.saves),
            ("Followers", headline.followers),
            ("Visits", headline.visits),
            ("QR Scans", headline.scans),
            ("Sign-ups", headline.signups),
            ("Redemptions", headline.redemptions)
        ]

        // 2 stat cards per row
        for pair in stride(from: 0, to: stats.count, by: 2) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = Constants.Spacing.medium
            for (title, number) in stats[pair..<min(pair + 2, stats.count)] {
                row.addArrangedSubview(makeStatCard(number: number, title: title))
            }
            statsGrid.addArrangedSubview(row)
        }

        if let detail = dashboard.detail {
            renderDetail(detail)
        } else {
            renderLockedCard()
        }
    }

    private func makeStatCard(number: Int, title: String) -> UIView {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12

        let stat = StatView()
        stat.translatesAutoresizingMaskIntoConstraints = false
        stat.configure(number: "\(number)", title: title)

        card.addSubview(stat)
        NSLayoutConstraint.activate([
            stat.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stat.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            card.heightAnchor.constraint(equalToConstant: 84)
        ])
        return card
    }

    private func renderDetail(_ detail: VenueDashboardDetail) {
        let header = UILabel()
        header.text = "Last 6 months"
        header.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        header.textColor = Constants.Colors.label
        detailSection.addArrangedSubview(header)

        let newSaves = UILabel()
        newSaves.text = "\(detail.newSavesThisMonth) new save\(detail.newSavesThisMonth == 1 ? "" : "s") this month"
        newSaves.font = UIFont.systemFont(ofSize: 14)
        newSaves.textColor = .secondaryLabel
        detailSection.addArrangedSubview(newSaves)

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM yyyy"

        for key in detail.monthly.keys.sorted(by: >) {
            let month = detail.monthly[key]!
            let row = UIView()
            row.backgroundColor = Constants.Colors.secondaryBackground
            row.layer.cornerRadius = 8

            let nameLabel = UILabel()
            nameLabel.text = monthFormatter.date(from: key).map { displayFormatter.string(from: $0) } ?? key
            nameLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            nameLabel.textColor = Constants.Colors.label
            nameLabel.translatesAutoresizingMaskIntoConstraints = false

            let valuesLabel = UILabel()
            valuesLabel.text = "Visits \(month.visits ?? 0) · Scans \(month.scans ?? 0) · Saves \(month.saves ?? 0) · Redeemed \(month.redemptions ?? 0)"
            valuesLabel.font = UIFont.systemFont(ofSize: 12)
            valuesLabel.textColor = .secondaryLabel
            valuesLabel.adjustsFontSizeToFitWidth = true
            valuesLabel.translatesAutoresizingMaskIntoConstraints = false

            row.addSubview(nameLabel)
            row.addSubview(valuesLabel)
            NSLayoutConstraint.activate([
                nameLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
                nameLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
                nameLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
                valuesLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
                valuesLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
                valuesLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
                valuesLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8)
            ])
            detailSection.addArrangedSubview(row)
        }
    }

    private func renderLockedCard() {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12

        let lockImage = UIImageView(image: UIImage(systemName: "lock.fill"))
        lockImage.tintColor = Constants.Colors.primary
        lockImage.contentMode = .scaleAspectFit
        lockImage.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Unlock full stats, announcements & loyalty"
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "See monthly trends, post announcements and offers, and run your loyalty program with FavCircles Business."
        subtitleLabel.font = UIFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let upgradeButton = UIButton.primaryButton(title: "Upgrade to Business")
        upgradeButton.addTarget(self, action: #selector(upgradeTapped), for: .touchUpInside)

        card.addSubview(lockImage)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(upgradeButton)
        NSLayoutConstraint.activate([
            lockImage.topAnchor.constraint(equalTo: card.topAnchor, constant: Constants.Spacing.large),
            lockImage.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            lockImage.widthAnchor.constraint(equalToConstant: 32),
            lockImage.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: lockImage.bottomAnchor, constant: Constants.Spacing.small),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Constants.Spacing.medium),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Constants.Spacing.medium),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Constants.Spacing.medium),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Constants.Spacing.medium),

            upgradeButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: Constants.Spacing.medium),
            upgradeButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Constants.Spacing.medium),
            upgradeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Constants.Spacing.medium),
            upgradeButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Constants.Spacing.medium)
        ])
        detailSection.addArrangedSubview(card)
    }

    @objc private func upgradeTapped() {
        let paywallVC = OwnerPaywallViewController()
        paywallVC.onSubscribed = { [weak self] in
            self?.loadData()
        }
        navigationController?.pushViewController(paywallVC, animated: true)
    }
}
