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
        let dates = events.compactMap { $0.createdAt }
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

        headerStack.addArrangedSubview(makeHistogram(
            title: "Busiest hours",
            values: byHour,
            labels: (0..<24).map { $0 % 6 == 0 ? String(format: "%d%@", $0 == 0 ? 12 : ($0 > 12 ? $0 - 12 : $0), $0 < 12 ? "a" : "p") : "" }
        ))
        headerStack.addArrangedSubview(makeHistogram(
            title: "Busiest days",
            values: byWeekday,
            labels: ["S", "M", "T", "W", "T", "F", "S"]
        ))

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

    private func makeHistogram(title: String, values: [Int], labels: [String]) -> UIView {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let barsStack = UIStackView()
        barsStack.axis = .horizontal
        barsStack.distribution = .fillEqually
        barsStack.alignment = .bottom
        barsStack.spacing = 2
        barsStack.translatesAutoresizingMaskIntoConstraints = false

        let labelsStack = UIStackView()
        labelsStack.axis = .horizontal
        labelsStack.distribution = .fillEqually
        labelsStack.spacing = 2
        labelsStack.translatesAutoresizingMaskIntoConstraints = false

        let maxValue = max(values.max() ?? 1, 1)
        let barMaxHeight: CGFloat = 48
        for (index, value) in values.enumerated() {
            let barWrapper = UIView()
            let bar = UIView()
            bar.backgroundColor = value > 0 ? Constants.Colors.primary : Constants.Colors.primary.withAlphaComponent(0.15)
            bar.layer.cornerRadius = 2
            bar.translatesAutoresizingMaskIntoConstraints = false
            barWrapper.addSubview(bar)
            let height = value > 0
                ? max(4, barMaxHeight * CGFloat(value) / CGFloat(maxValue))
                : 3
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: barWrapper.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: barWrapper.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: barWrapper.bottomAnchor),
                bar.heightAnchor.constraint(equalToConstant: height),
                barWrapper.heightAnchor.constraint(equalToConstant: barMaxHeight)
            ])
            barsStack.addArrangedSubview(barWrapper)

            let label = UILabel()
            label.text = index < labels.count ? labels[index] : ""
            label.font = UIFont.systemFont(ofSize: 9)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            labelsStack.addArrangedSubview(label)
        }

        card.addSubview(titleLabel)
        card.addSubview(barsStack)
        card.addSubview(labelsStack)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            barsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            barsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            barsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            labelsStack.topAnchor.constraint(equalTo: barsStack.bottomAnchor, constant: 2),
            labelsStack.leadingAnchor.constraint(equalTo: barsStack.leadingAnchor),
            labelsStack.trailingAnchor.constraint(equalTo: barsStack.trailingAnchor),
            labelsStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
        ])
        return card
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
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
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
        let (verb, icon): (String, String)
        switch event.type {
        case "venue_visit": (verb, icon) = ("visited (register scan)", "qrcode.viewfinder")
        case "sticker_signup": (verb, icon) = ("joined from your sticker", "person.badge.plus")
        case "sticker_save": (verb, icon) = ("saved your place", "bookmark.fill")
        case "redemption":
            let title = event.offerTitle.map { " — \($0)" } ?? ""
            (verb, icon) = ("redeemed a reward\(title)", "gift.fill")
        case "code_redemption": (verb, icon) = ("redeemed a code", "number.square.fill")
        case "share_conversion": (verb, icon) = ("brought a friend", "person.2.fill")
        default: (verb, icon) = (event.type.replacingOccurrences(of: "_", with: " "), "sparkles")
        }
        titleLabel.text = "\(who) \(verb)"
        iconView.image = UIImage(systemName: icon)

        if let date = event.createdAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            subtitleLabel.text = formatter.string(from: date)
        } else {
            subtitleLabel.text = nil
        }
    }
}
