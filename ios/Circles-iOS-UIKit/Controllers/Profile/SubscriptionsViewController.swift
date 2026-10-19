import UIKit
import StoreKit

/// Settings → Subscriptions: everything a person pays FavCircles for, in one
/// place (Wes, 2026-10-19: a $7.99 charge he couldn't place — Fridge Mail,
/// billed by card — and a cancel button that was hard to find).
///
/// The server lists them (GET users/subscription/all); Apple's ones get their
/// price and renew/end state from the App Store itself, since only Apple knows
/// whether a subscription will renew. Apple subscriptions can only be canceled
/// in the App Store; Fridge Mail is canceled right here.
final class SubscriptionsViewController: BaseTableViewController {

    struct Entry: Decodable {
        let id: String
        let name: String
        let what: String
        let billedBy: String          // "apple" | "card"
        let productId: String?
        let period: String            // "month" | "year"
        var priceCents: Int?
        let quantity: Int?
        let status: String            // "active" | "payment_issue"
        var periodEnd: String?
        var willRenew: Bool?
        let manage: String            // "appstore" | "fridgemail"

        /// From the App Store, for Apple subscriptions
        var storePrice: String?
        var storeEnd: Date?
    }

    private struct ListResponse: Decodable { let subscriptions: [Entry] }

    private enum Row { case summary, price, status, action }
    private let rows: [Row] = [.summary, .price, .status, .action]

    private var entries: [Entry] = []
    private var busyId: String?

    override var emptyStateMessage: String? { nil }

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        title = "Subscriptions"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        super.viewDidLoad()
    }

    // MARK: - Loading

    override func loadData(completion: (() -> Void)? = nil) {
        APIService.shared.request(endpoint: "users/subscription/all") { [weak self] (result: Result<ListResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self else { completion?(); return }
                switch result {
                case .success(let response):
                    self.entries = response.subscriptions
                    self.tableView.reloadData()
                    Task { await self.fillFromAppStore(); completion?() }
                case .failure(let error):
                    self.showError(error.serverMessage ?? "Couldn't load your subscriptions.")
                    completion?()
                }
            }
        }
    }

    /// Apple's price, renewal date and whether it will renew
    @MainActor
    private func fillFromAppStore() async {
        for index in entries.indices where entries[index].billedBy == "apple" {
            guard let productId = entries[index].productId,
                  let product = try? await Product.products(for: [productId]).first else { continue }
            entries[index].storePrice = product.displayPrice
            guard let statuses = try? await product.subscription?.status else { continue }
            for status in statuses {
                guard case .verified(let transaction) = status.transaction, transaction.productID == productId else { continue }
                if case .verified(let renewal) = status.renewalInfo { entries[index].willRenew = renewal.willAutoRenew }
                entries[index].storeEnd = transaction.expirationDate
            }
        }
        tableView.reloadData()
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { max(entries.count, 1) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.isEmpty ? (hasLoadedData ? 1 : 0) : rows.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == max(entries.count, 1) - 1 else { return nil }
        return "Premium and Business are billed by Apple, so they're canceled in the App Store (Apple doesn't let apps do it). Fridge Mail is billed to your card by FavCircles and can be canceled here. Canceling keeps everything working until the end of the period you've paid for."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        guard !entries.isEmpty else {
            cell.textLabel?.text = "You don't have any subscriptions."
            cell.textLabel?.textColor = Constants.Colors.secondaryLabel
            return cell
        }
        let entry = entries[indexPath.section]
        switch rows[indexPath.row] {
        case .summary:
            cell.textLabel?.text = entry.name
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            cell.detailTextLabel?.text = entry.what
            cell.detailTextLabel?.textColor = Constants.Colors.secondaryLabel
        case .price:
            cell.textLabel?.text = priceLine(entry)
            cell.detailTextLabel?.text = entry.billedBy == "apple" ? "Billed by Apple" : "Billed to your card by FavCircles"
            cell.detailTextLabel?.textColor = Constants.Colors.secondaryLabel
        case .status:
            let (text, isWarning) = statusLine(entry)
            cell.textLabel?.text = text
            cell.textLabel?.textColor = isWarning ? .systemRed : Constants.Colors.label
        case .action:
            let (title, isCancel) = actionTitle(entry)
            cell.textLabel?.text = busyId == entry.id ? "Working…" : title
            cell.textLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            cell.textLabel?.textColor = isCancel ? .systemRed : Constants.Colors.primary
            cell.selectionStyle = .default
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !entries.isEmpty, rows[indexPath.row] == .action, busyId == nil else { return }
        let entry = entries[indexPath.section]
        switch entry.manage {
        case "fridgemail": changeFridgeMail(entry)
        default: openAppStore()
        }
    }

    // MARK: - Words

    private func priceLine(_ entry: Entry) -> String {
        let per = entry.period == "year" ? "year" : "month"
        if let store = entry.storePrice { return "\(store) a \(per)" }
        guard let cents = entry.priceCents else { return entry.period == "year" ? "Yearly" : "Monthly" }
        let price = Self.dollars(cents)
        if let quantity = entry.quantity, quantity > 1, let unit = entry.priceCents.map({ $0 / quantity }) {
            return "\(price) a \(per) (\(quantity) × \(Self.dollars(unit)))"
        }
        return "\(price) a \(per)"
    }

    private func statusLine(_ entry: Entry) -> (String, Bool) {
        if entry.status == "payment_issue" { return ("There's a problem with the payment", true) }
        let end = entry.storeEnd ?? entry.periodEnd.flatMap(Self.parseDate)
        let date = end.map { $0.formatted(date: .long, time: .omitted) }
        switch entry.willRenew {
        case .some(false): return (date.map { "Canceled · ends \($0)" } ?? "Canceled", false)
        case .some(true): return (date.map { "Renews \($0)" } ?? "Active", false)
        case .none: return (date.map { "Paid through \($0)" } ?? "Active", false)
        }
    }

    private func actionTitle(_ entry: Entry) -> (String, Bool) {
        if entry.manage == "fridgemail" {
            return entry.willRenew == false ? ("Keep my subscription", false) : ("Cancel subscription", true)
        }
        return entry.willRenew == false ? ("Resubscribe in the App Store", false) : ("Cancel or change in the App Store", true)
    }

    private static func dollars(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$\(cents / 100)"
    }

    private static func parseDate(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    // MARK: - Actions

    private func openAppStore() {
        guard let scene = view.window?.windowScene else { return }
        Task {
            try? await AppStore.showManageSubscriptions(in: scene)
            loadData()
        }
    }

    private func changeFridgeMail(_ entry: Entry) {
        if entry.willRenew == false {
            runFridgeMail("resume", entry)
            return
        }
        let end = entry.periodEnd.flatMap(Self.parseDate).map { $0.formatted(date: .long, time: .omitted) }
        AlertPresenter.showConfirmation(
            title: "Cancel Fridge Mail?",
            message: "You won't be charged again. Weekly cards keep going until \(end ?? "the end of this month").",
            confirmTitle: "Cancel subscription",
            cancelTitle: "Keep it",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in self?.runFridgeMail("cancel", entry) }
        )
    }

    private struct PlanResponse: Decodable {}

    private func runFridgeMail(_ action: String, _ entry: Entry) {
        busyId = entry.id
        tableView.reloadData()
        APIService.shared.request(endpoint: "widgets/fridgemail/subscription/\(action)", method: .post) { [weak self] (result: Result<PlanResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busyId = nil
                switch result {
                case .success:
                    AlertPresenter.showBriefMessage(action == "cancel" ? "Fridge Mail canceled" : "Fridge Mail will keep going", from: self)
                    self.loadData()
                case .failure(let error):
                    self.tableView.reloadData()
                    self.showError(error.serverMessage ?? "Couldn't change Fridge Mail. Try again.")
                }
            }
        }
    }
}
