import UIKit

/// Owner management of single-use loyalty codes — the cards packed into
/// shipped orders or handed out at a conference booth. Mint a batch, share
/// the codes (print/CSV via the share sheet), and watch redemptions.
class VenueCodesViewController: BaseViewController {

    private let venueId: String
    private let venueName: String
    private var codes: [RedemptionCodeSummary] = []
    private var summary: RedemptionCodeListData.RedemptionCodeListSummary?

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        "No codes yet.\nMint a batch and pack one into every order — customers scan or type the code and earn loyalty points."
    }

    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 56
        return table
    }()

    init(venueId: String, venueName: String) {
        self.venueId = venueId
        self.venueName = venueName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Loyalty Codes"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(newBatchTapped))

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CodeCell")

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

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.listRedemptionCodes(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self = self else { return }
                switch result {
                case .success(let data):
                    self.codes = data.codes
                    self.summary = data.summary
                    self.tableView.reloadData()
                    self.codes.isEmpty ? self.showEmptyState() : self.hideEmptyState()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Minting

    @objc private func newBatchTapped() {
        let alert = UIAlertController(
            title: "New Code Batch",
            message: "Single-use codes worth loyalty points at \(venueName)",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "How many codes (1–500)"
            field.keyboardType = .numberPad
            field.text = "50"
        }
        alert.addTextField { field in
            field.placeholder = "Points per code (1–1000)"
            field.keyboardType = .numberPad
            field.text = "50"
        }
        alert.addTextField { field in
            field.placeholder = "Batch label (optional)"
        }
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let count = Int(alert?.textFields?[0].text ?? ""),
                  let points = Int(alert?.textFields?[1].text ?? "") else { return }
            let label = alert?.textFields?[2].text
            self.mintBatch(count: count, points: points, label: label)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func mintBatch(count: Int, points: Int, label: String?) {
        let loading = AlertPresenter.showLoading(from: self)
        RewardsService.shared.createRedemptionCodes(venueId: venueId, count: count, points: points, label: label) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let batch):
                        self.loadData()
                        self.shareBatch(batch)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    /// Hand the batch off as text — print shop, CSV, notes, wherever
    private func shareBatch(_ batch: RedemptionCodeBatchData) {
        var lines = ["\(venueName) loyalty codes — \(batch.points) points each"]
        if let label = batch.label, !label.isEmpty { lines.append("Batch: \(label)") }
        lines.append("")
        lines.append(contentsOf: batch.codes)
        let text = lines.joined(separator: "\n")
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        present(activityVC, animated: true)
    }
}

// MARK: - Table
extension VenueCodesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return codes.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let summary = summary, summary.total > 0 else { return nil }
        return "\(summary.redeemed) of \(summary.total) redeemed"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CodeCell", for: indexPath)
        let code = codes[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = code.code
        config.textProperties.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .semibold)
        var detail = "\(code.points) pts"
        if let label = code.label, !label.isEmpty { detail += " · \(label)" }
        detail += code.active ? " · unredeemed" : " · redeemed"
        config.secondaryText = detail
        config.secondaryTextProperties.color = code.active ? .secondaryLabel : Constants.Colors.success
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }
}
