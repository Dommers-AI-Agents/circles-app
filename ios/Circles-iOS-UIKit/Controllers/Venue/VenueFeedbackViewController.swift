import UIKit

/// Manage Store → Private feedback (2026-11-02): stars and notes customers
/// sent only to the store's team from "Enjoying <store>?". Newest first.
/// A `store_feedback` push opens this screen.
final class VenueFeedbackViewController: BaseViewController {

    private let venueId: String
    private var feedback: [StoreFeedbackEntry] = []

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        "No private feedback yet.\nAfter a customer gets a reward, they can rate your store and leave a note only your team sees."
    }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 72
        return table
    }()

    init(venueId: String) {
        self.venueId = venueId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Private Feedback"
        view.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.allowsSelection = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FeedbackCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if navigationController?.viewControllers.first === self {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeTapped))
        }
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.fetchStoreFeedback(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let feedback):
                    self.feedback = feedback
                    self.tableView.reloadData()
                    feedback.isEmpty ? self.showEmptyState() : self.hideEmptyState()
                case .failure(let error):
                    // A failed refresh keeps what's showing
                    self.showError(error)
                }
            }
        }
    }
}

extension VenueFeedbackViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { feedback.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FeedbackCell", for: indexPath)
        let entry = feedback[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = StoreFeedbackCopy.headline(entry)
        config.secondaryText = StoreFeedbackCopy.detail(entry)
        config.secondaryTextProperties.numberOfLines = 0
        config.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = config
        return cell
    }
}

/// The words for one private feedback row. Pure.
enum StoreFeedbackCopy {
    /// "★★★★☆ Ann"
    static func headline(_ entry: StoreFeedbackEntry) -> String {
        let stars = max(0, min(5, entry.rating))
        let name = entry.user?.displayName ?? "A customer"
        return String(repeating: "\u{2605}", count: stars) + String(repeating: "\u{2606}", count: 5 - stars) + " " + name
    }

    /// The note, then when: "Great smoothies · today 3:10 PM"
    static func detail(_ entry: StoreFeedbackEntry, calendar: Calendar = .current, now: Date = Date()) -> String {
        let when = RewardTicketCopy.date(entry.createdAt).map { RewardTicketCopy.dayAndTime($0, calendar: calendar, now: now) }
        return [entry.note, when].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}
