import UIKit

/// The venue's loyalty ledger: every scan, sign-up, save, and redemption with
/// who and when, plus busiest-hours / busiest-days histograms computed from
/// the timestamps. The owner watching customers scan at the register is the
/// physical version of this screen — a digital punch card, not surveillance.
class VenueActivityViewController: BaseViewController {

    // MARK: - Properties

    private let venueId: String
    private var events: [VenueActivityEvent] = []

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        "No activity yet. Scans, sign-ups, saves, and redemptions will appear here."
    }

    // MARK: - UI

    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = 56
        table.tableFooterView = UIView()
        return table
    }()

    private let headerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.medium
        return stack
    }()

    // MARK: - Init

    init(venueId: String) {
        self.venueId = venueId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Visits & Scans"
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.register(VenueActivityCell.self, forCellReuseIdentifier: VenueActivityCell.reuseId)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    // MARK: - Data

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.getVenueActivity(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self = self else { return }
                switch result {
                case .success(let data):
                    self.events = data.events
                    self.renderHeader()
                    self.tableView.reloadData()
                    if self.events.isEmpty { self.showEmptyState() } else { self.hideEmptyState() }
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Histograms

    private func renderHeader() {
        headerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Scans that earned nothing are listed but not counted as busy times
        let dates = events.filter { !VenueActivityCopy.attemptTypes.contains($0.type) }.compactMap { $0.createdAt }
        guard !dates.isEmpty else {
            tableView.tableHeaderView = nil
            return
        }

        // Device timezone ≈ venue timezone (the owner is at their store)
        let calendar = Calendar.current
        var byHour = [Int](repeating: 0, count: 24)
        var byWeekday = [Int](repeating: 0, count: 7)
        for date in dates {
            byHour[calendar.component(.hour, from: date)] += 1
            byWeekday[calendar.component(.weekday, from: date) - 1] += 1
        }

        headerStack.addArrangedSubview(HistogramCardView.make(title: "Busiest hours", values: byHour, labels: HistogramCardView.hourLabels))
        headerStack.addArrangedSubview(HistogramCardView.make(title: "Busiest days", values: byWeekday, labels: HistogramCardView.dayLabels))

        let recentHeader = UILabel()
        recentHeader.text = "Recent activity"
        recentHeader.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        recentHeader.textColor = Constants.Colors.label
        headerStack.addArrangedSubview(recentHeader)

        let width = tableView.bounds.width
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 0))
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: Constants.Spacing.medium),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.Spacing.medium),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Constants.Spacing.medium),
            headerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Constants.Spacing.small)
        ])
        let height = container.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        ).height
        container.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tableView.tableHeaderView = container
    }

}

// MARK: - UITableViewDataSource

extension VenueActivityViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        events.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VenueActivityCell.reuseId, for: indexPath) as! VenueActivityCell
        cell.configure(with: events[indexPath.row])
        return cell
    }
}

// MARK: - Cell

class VenueActivityCell: UITableViewCell {
    static let reuseId = "VenueActivityCell"

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Constants.Colors.primary
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with event: VenueActivityEvent) {
        let who = event.user?.displayName ?? "A customer"
        let (verb, icon) = VenueActivityCopy.verb(type: event.type, location: event.location, offerTitle: event.offerTitle)
        titleLabel.text = "\(who) \(verb)"
        iconView.image = UIImage(systemName: icon)

        subtitleLabel.text = event.createdAt.map { VenueActivityCopy.time($0) }
    }
}
