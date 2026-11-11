import UIKit

/// Help → Show Someone How (Scan Actions, 2026-11-11): each "show me how"
/// guide, to run yourself or to hold up as a QR for someone else (it walks
/// them through it in their own app). The list comes from the server
/// (backend/config/scanGuides.js), so a new guide needs no app update.
final class ScanGuidesViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate {
    override var emptyStateMessage: String? { "No guides right now." }

    struct Guide: Decodable {
        let id: String
        let appGuide: String
        let title: String
        let blurb: String
        let storeOwner: Bool
    }
    private struct GuideList: Decodable { let guides: [Guide] }
    private struct Envelope: Decodable { let success: Bool; let data: GuideList }

    private var guides: [Guide] = []
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Show Someone How"
        view.backgroundColor = Constants.Colors.groupedBackground
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func loadData(completion: (() -> Void)? = nil) {
        APIService.shared.request(endpoint: "scan-actions/guides", method: .get, requiresAuth: false) { [weak self] (result: Result<Envelope, APIError>) in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let envelope):
                    // Only guides this build can run
                    self.guides = envelope.data.guides.filter { ScreenGuideKind(rawValue: $0.appGuide)?.isScannable == true }
                    self.tableView.reloadData()
                    if self.guides.isEmpty { self.showEmptyState() } else { self.hideEmptyState() }
                case .failure(let error):
                    self.showErrorWithRetry(error) { [weak self] in self?.loadData() }
                }
            }
        }
    }

    private func sections() -> [[Guide]] {
        [guides.filter { !$0.storeOwner }, guides.filter(\.storeOwner)].filter { !$0.isEmpty }
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections().count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections()[section].count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections()[section].first?.storeOwner == true ? "For store owners" : nil
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "Tap one to try it, or show its QR: whoever scans it gets walked through it in their own FavCircles." : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let guide = sections()[indexPath.section][indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var config = UIListContentConfiguration.subtitleCell()
        config.text = guide.title
        config.secondaryText = guide.blurb
        config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
        config.image = UIImage(systemName: guide.storeOwner ? "storefront" : "hand.point.up.left")
        config.imageProperties.tintColor = Constants.Colors.primary
        cell.contentConfiguration = config
        cell.backgroundColor = .secondarySystemGroupedBackground
        let qr = UIButton.iconButton(systemName: "qrcode", pointSize: 20)
        qr.accessibilityLabel = "Show the QR for \(guide.title)"
        qr.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        qr.addAction(UIAction { [weak self] _ in self?.showQR(guide) }, for: .touchUpInside)
        cell.accessoryView = qr
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let guide = sections()[indexPath.section][indexPath.row]
        guard let kind = ScreenGuideKind(rawValue: guide.appGuide) else { return }
        AlertPresenter.showActionSheet(title: guide.title, message: guide.blurb, actions: [
            ("Walk Me Through It", .default, { ScanActionCoordinator.shared.runGuide(kind) }),
            ("Show the QR", .default, { [weak self] in self?.showQR(guide) })
        ], from: self, sourceView: tableView.cellForRow(at: indexPath))
    }

    private func showQR(_ guide: Guide) {
        ScanCodeSheetViewController.presentGuide(id: guide.id, title: guide.title, blurb: guide.blurb, from: self)
    }
}
