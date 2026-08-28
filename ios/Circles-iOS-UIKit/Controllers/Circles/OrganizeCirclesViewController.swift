import UIKit

// MARK: - Organize circles
//
// Shows what the advisor noticed about the circles: which organizing scheme
// each one uses, and which ones overlap enough to be worth combining.
//
// Everything here is a proposal. Nothing is applied until it's approved one at
// a time, because merging circles moves somebody's saved places and a single
// "apply all" button is a very fast way to lose an organization scheme that
// took years to build.

final class OrganizeCirclesViewController: BaseViewController {

    // MARK: Models

    struct SchemeLabel: Codable {
        let circleId: String
        let scheme: String
        let confidence: Double
    }

    struct MergeProposal: Codable {
        let circleIds: [String]
        let keepCircleId: String
        let suggestedName: String
        let reason: String
    }

    private struct AdviceResponse: Codable {
        let success: Bool
        let enabled: Bool
        let schemes: [SchemeLabel]
        let merges: [MergeProposal]
        /// True when the answer came from cache — no model call was made, and
        /// it didn't consume one of the day's runs.
        let cached: Bool?
        /// Runs left today after this one. Absent on a cached answer.
        let remaining: Int?
    }

    /// Human labels for the schemes the advisor assigns.
    private static let schemeTitles: [String: String] = [
        "place": "By place",
        "type": "By type",
        "person": "By person",
        "trip": "Trips",
        "system": "Created by Circles",
        "unclear": "Uncategorized"
    ]

    /// The order sections appear in — most-populated schemes first, with the
    /// app's own circles and the leftovers at the bottom.
    private static let schemeOrder = ["place", "type", "person", "trip", "system", "unclear"]

    // MARK: State

    private var circles: [Circle] = []
    private var schemes: [String: String] = [:]   // circleId -> scheme
    private var merges: [MergeProposal] = []
    /// Merges already acted on this session, so an approved row doesn't linger.
    private var resolvedMergeIndices = Set<Int>()

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        "Nothing to reorganize — your circles already look tidy."
    }

    // MARK: Lifecycle

    init(circles: [Circle]) {
        self.circles = circles
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar(title: "Organize", largeTitleMode: .never)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissSelf)
        )

        view.addSubview(tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "OrganizeCell")
        tableView.refreshControl = refreshControl

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    // MARK: Data

    override func loadData(completion: (() -> Void)? = nil) {
        APIService.shared.request(
            endpoint: "circles/advisor",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<AdviceResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                completion?()

                switch result {
                case .success(let response):
                    guard response.enabled else {
                        self.showEmptyState(message: "Circle suggestions aren't switched on yet.")
                        return
                    }
                    self.schemes = Dictionary(
                        response.schemes.map { ($0.circleId, $0.scheme) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    self.merges = response.merges
                    self.resolvedMergeIndices.removeAll()
                    self.tableView.reloadData()

                    if self.schemes.isEmpty && self.merges.isEmpty {
                        self.showEmptyState(message: self.emptyStateMessage)
                    } else {
                        self.hideEmptyState()
                    }

                case .failure(let error):
                    self.handleAdviceFailure(error)
                }
            }
        }
    }

    /// The server is the authority on both entitlement and spend, so the
    /// interesting failures arrive as status codes rather than as anything the
    /// client could have known in advance.
    private func handleAdviceFailure(_ error: APIError) {
        switch error {
        case .httpError(402, _):
            presentPaywall()
        case .httpError(429, _), .rateLimited:
            // Out of runs — a real answer, not a fault. Say what happened and
            // when it changes, rather than showing a generic error.
            showEmptyState(message: error.serverMessage
                ?? "You've used today's circle suggestions. They reset tomorrow.")
        default:
            showError(error)
        }
    }

    private func presentPaywall() {
        AlertPresenter.showConfirmation(
            title: "Circle suggestions are a Premium feature",
            message: "Premium reads through your circles and points out which ones overlap enough to combine.",
            confirmTitle: "See Premium",
            cancelTitle: "Not now",
            from: self,
            onConfirm: { [weak self] in
                guard let self = self else { return }
                // Dismiss this sheet first so the paywall lands on the profile's
                // own navigation stack rather than stacking on a modal.
                let presenting = self.presentingViewController
                self.dismiss(animated: true) {
                    guard let nav = (presenting as? UITabBarController)?.selectedViewController
                            as? UINavigationController
                            ?? presenting?.navigationController else { return }
                    nav.pushViewController(SubscriptionViewController(), animated: true)
                }
            },
            onCancel: { [weak self] in self?.dismiss(animated: true) }
        )
    }

    // MARK: Derived sections

    /// Merge proposals still awaiting a decision.
    private var pendingMerges: [(index: Int, proposal: MergeProposal)] {
        merges.enumerated()
            .filter { !resolvedMergeIndices.contains($0.offset) }
            .map { (index: $0.offset, proposal: $0.element) }
    }

    /// Scheme groups that actually contain circles, in canonical order.
    private var groupedSchemes: [(scheme: String, circles: [Circle])] {
        Self.schemeOrder.compactMap { scheme in
            let matching = circles.filter { schemes[$0.id] == scheme }
            guard !matching.isEmpty else { return nil }
            // Within a group keep the user's own circle order (as on the profile)
            return (scheme: scheme, circles: matching)
        }
    }

    private func circle(withId id: String) -> Circle? {
        circles.first { $0.id == id }
    }

    // MARK: Merge

    private func confirmMerge(_ proposal: MergeProposal) {
        let absorbed = proposal.circleIds
            .filter { $0 != proposal.keepCircleId }
            .compactMap { circle(withId: $0)?.name }

        guard let keeper = circle(withId: proposal.keepCircleId) else { return }

        AlertPresenter.showConfirmation(
            title: "Combine into \(keeper.name)?",
            message: "Places from \(absorbed.joined(separator: " and ")) move into \(keeper.name). "
                + "The emptied circles go to your trash — restoring one brings the circle back, "
                + "but the places stay where they moved.",
            confirmTitle: "Combine",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in self?.performMerge(proposal) }
        )
    }

    private struct MergeResult: Codable {
        let success: Bool
        let keepCircleId: String
        let movedPlaces: Int
        let retiredCircles: [String]
    }

    private func performMerge(_ proposal: MergeProposal) {
        // One server call rather than a client-driven loop of moves and
        // deletes: a half-finished merge would leave places stranded in a
        // circle that's already gone, and the ordering that prevents that
        // belongs next to the data, not in a view controller.
        let body: [String: Any] = [
            "circleIds": proposal.circleIds,
            "keepCircleId": proposal.keepCircleId,
            "name": proposal.suggestedName
        ]

        APIService.shared.request(
            endpoint: "circles/advisor/merge",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<MergeResult, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let merged):
                    self.applyMergeLocally(proposal, moved: merged.movedPlaces)
                case .failure(let error):
                    if case .httpError(402, _) = error {
                        self.presentPaywall()
                    } else {
                        self.showError(error)
                    }
                }
            }
        }
    }

    /// Reflects a completed merge without a round trip, and tells the profile
    /// its circle list is stale.
    private func applyMergeLocally(_ proposal: MergeProposal, moved: Int) {
        let retired = Set(proposal.circleIds.filter { $0 != proposal.keepCircleId })
        circles.removeAll { retired.contains($0.id) }

        if let index = merges.firstIndex(where: { $0.keepCircleId == proposal.keepCircleId
            && $0.circleIds == proposal.circleIds }) {
            resolvedMergeIndices.insert(index)
        }

        tableView.reloadData()
        // The profile already listens for this to reload its grid.
        NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)

        let placeText = moved == 1 ? "1 place" : "\(moved) places"
        AlertPresenter.showSuccess(
            "\(placeText) moved into \(proposal.suggestedName). The emptied circles are in your trash.",
            from: self
        )
    }
}

// MARK: - Table

extension OrganizeCirclesViewController: UITableViewDataSource, UITableViewDelegate {

    private enum Section: Int, CaseIterable {
        case merges
        case schemes
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        // Merge proposals occupy one section; each scheme group gets its own.
        (pendingMerges.isEmpty ? 0 : 1) + groupedSchemes.count
    }

    private func isMergeSection(_ section: Int) -> Bool {
        !pendingMerges.isEmpty && section == 0
    }

    private func schemeGroup(for section: Int) -> (scheme: String, circles: [Circle]) {
        let offset = pendingMerges.isEmpty ? 0 : 1
        return groupedSchemes[section - offset]
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isMergeSection(section) ? pendingMerges.count : schemeGroup(for: section).circles.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if isMergeSection(section) {
            let count = pendingMerges.count
            return count == 1 ? "1 suggested merge" : "\(count) suggested merges"
        }
        let group = schemeGroup(for: section)
        return Self.schemeTitles[group.scheme] ?? group.scheme.capitalized
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        isMergeSection(section) ? "Tap one to review it. Nothing changes until you confirm." : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "OrganizeCell", for: indexPath)
        var config = cell.defaultContentConfiguration()

        if isMergeSection(indexPath.section) {
            let proposal = pendingMerges[indexPath.row].proposal
            config.text = proposal.suggestedName
            config.secondaryText = proposal.reason
            config.secondaryTextProperties.numberOfLines = 0
            config.image = UIImage(systemName: "arrow.triangle.merge")
            cell.accessoryType = .disclosureIndicator
        } else {
            let circle = schemeGroup(for: indexPath.section).circles[indexPath.row]
            config.text = circle.name
            let count = circle.placesCount ?? 0
            config.secondaryText = count == 1 ? "1 place" : "\(count) places"
            config.image = UIImage(systemName: "circle.grid.2x2")
            cell.accessoryType = .none
        }

        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard isMergeSection(indexPath.section) else { return }
        confirmMerge(pendingMerges[indexPath.row].proposal)
    }

    /// Dismissing a proposal is as valid an answer as accepting it.
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard isMergeSection(indexPath.section) else { return nil }
        let entry = pendingMerges[indexPath.row]

        let dismiss = UIContextualAction(style: .destructive, title: "Dismiss") { [weak self] _, _, done in
            guard let self = self else { return done(false) }
            self.resolvedMergeIndices.insert(entry.index)
            self.tableView.reloadData()
            done(true)
        }
        dismiss.image = UIImage(systemName: "xmark")
        return UISwipeActionsConfiguration(actions: [dismiss])
    }
}
