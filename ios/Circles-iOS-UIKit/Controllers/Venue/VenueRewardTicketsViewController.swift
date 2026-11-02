import UIKit

/// Manage Store → Rewards used (2026-11-01): every reward redeemed at the
/// store, newest first, with who, what, when, and whether staff handed it
/// over, it's still open, or it ran out and the points went back.
final class VenueRewardTicketsViewController: BaseViewController {

    private let venueId: String
    private var tickets: [VenueRewardTicket] = []

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        "No rewards used yet.\nWhen a customer redeems an offer, it shows here, and turns green once staff tap Given on their phone."
    }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 60
        return table
    }()

    init(venueId: String) {
        self.venueId = venueId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Rewards Used"
        view.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TicketCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.fetchVenueRewardTickets(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let tickets):
                    self.tickets = tickets
                    self.tableView.reloadData()
                    tickets.isEmpty ? self.showEmptyState() : self.hideEmptyState()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}

extension VenueRewardTicketsViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { tickets.count }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        tickets.isEmpty ? nil : "Given = staff tapped Given on the customer\u{2019}s phone. A reward not given within 15 minutes expires and the customer gets the points back."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TicketCell", for: indexPath)
        let ticket = tickets[indexPath.row]
        let line = VenueRewardTicketCopy.line(ticket)
        var config = cell.defaultContentConfiguration()
        config.text = "\(ticket.customerName) \u{00B7} \(ticket.offerTitle)"
        config.secondaryText = line.detail
        config.secondaryTextProperties.color = .secondaryLabel
        config.image = UIImage(systemName: line.symbol)
        config.imageProperties.tintColor = line.status == "given" ? .systemGreen : (line.status == "issued" ? .systemBlue : .systemOrange)
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }
}

/// The words for one row of the store's "Rewards used". Pure.
enum VenueRewardTicketCopy {
    struct Line: Equatable { let detail: String; let symbol: String; let status: String }

    static func line(_ ticket: VenueRewardTicket, calendar: Calendar = .current, now: Date = Date()) -> Line {
        let when = RewardTicketCopy.date(ticket.createdAt).map { RewardTicketCopy.dayAndTime($0, calendar: calendar, now: now) } ?? ""
        switch ticket.status {
        case "given":
            let given = RewardTicketCopy.date(ticket.givenAt).map { RewardTicketCopy.dayAndTime($0, calendar: calendar, now: now) } ?? when
            return Line(detail: "Given \(given) \u{00B7} \(ticket.pointsCost) pts \u{00B7} code \(ticket.voucherCode)", symbol: "checkmark.circle.fill", status: "given")
        case "expired":
            return Line(detail: "Not given \u{00B7} points returned \u{00B7} \(when)", symbol: "arrow.uturn.backward.circle.fill", status: "expired")
        default:
            return Line(detail: "Open now \u{00B7} code \(ticket.voucherCode) \u{00B7} \(when)", symbol: "ticket.fill", status: "issued")
        }
    }
}
