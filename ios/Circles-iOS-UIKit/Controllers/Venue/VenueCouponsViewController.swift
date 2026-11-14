import UIKit

/// Manage Store → Coupons (Business, 2026-11-14): the store's flyer and
/// mailer coupons, each with its QR link and how the campaign is doing.
/// Tap one for its QR, numbers, and to edit or pause it.
final class VenueCouponsViewController: BaseViewController {

    private let venueId: String
    private let venueName: String
    private var coupons: [VenueCoupon] = []

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { coupons.isEmpty ? StoreCouponCopy.empty : nil }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    init(venueId: String, venueName: String) {
        self.venueId = venueId
        self.venueName = venueName
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = StoreCouponCopy.rowTitle
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func setupRefreshControl() { tableView.refreshControl = refreshControl }

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.fetchCoupons(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let coupons):
                    self.coupons = coupons
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    @objc private func addTapped() {
        openForm(coupon: nil)
    }

    private func openForm(coupon: VenueCoupon?) {
        let form = VenueCouponFormViewController(venueId: venueId, coupon: coupon)
        form.onSaved = { [weak self] coupons, created in
            guard let self else { return }
            self.coupons = coupons
            self.tableView.reloadData()
            // A new coupon: straight to its QR, the thing they came for
            if let created { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.showQR(created) } }
        }
        navigationController?.pushViewController(form, animated: true)
    }

    private func showQR(_ coupon: VenueCoupon) {
        guard let url = coupon.url else { return }
        let qr = VenueQRViewController(venueName: "\(venueName)\n\(coupon.title)", stickerUrl: url,
                                       screenTitle: "Coupon QR", caption: StoreCouponCopy.qrCaption)
        navigationController?.pushViewController(qr, animated: true)
    }

    private func openCoupon(_ coupon: VenueCoupon) {
        let numbers = StoreCouponCopy.tiles(coupon).map { "\($0.title): \($0.value)" }.joined(separator: "\n")
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = [
            (title: "Show the QR", style: .default, handler: { [weak self] in self?.showQR(coupon) }),
            (title: "Share the link", style: .default, handler: { [weak self] in self?.shareLink(coupon) }),
            (title: "Edit", style: .default, handler: { [weak self] in self?.openForm(coupon: coupon) })
        ]
        if coupon.state != "ended" {
            actions.append((title: coupon.active ? "Pause" : "Resume", style: .default, handler: { [weak self] in self?.setActive(coupon, !coupon.active) }))
        }
        actions.append((title: "Delete", style: .destructive, handler: { [weak self] in self?.confirmDelete(coupon) }))
        actions.append((title: "Cancel", style: .cancel, handler: {}))
        AlertPresenter.showActionSheet(title: coupon.title, message: numbers, actions: actions, from: self)
    }

    private func shareLink(_ coupon: VenueCoupon) {
        guard let text = coupon.url, let url = URL(string: text) else { return }
        // One bubble (memory: shares-one-bubble): the link carries the words
        let item = LinkPreviewItem(url: url, title: StoreCouponCopy.shareTitle(storeName: venueName, coupon: coupon),
                                   image: QRCodeRenderer.image(for: text, correction: "H"))
        let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        present(sheet, animated: true)
    }

    private func setActive(_ coupon: VenueCoupon, _ active: Bool) {
        RewardsService.shared.updateCoupon(venueId: venueId, couponId: coupon.couponId, body: ["active": active]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let saved):
                    self.coupons = saved.coupons
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    private func confirmDelete(_ coupon: VenueCoupon) {
        showConfirmation(title: "Delete \(coupon.title)?",
                         message: "Its QR stops working. People who already claimed it keep theirs until it ends.",
                         confirmTitle: "Delete") { [weak self] in
            guard let self else { return }
            RewardsService.shared.deleteCoupon(venueId: self.venueId, couponId: coupon.couponId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let coupons):
                        self.coupons = coupons
                        self.tableView.reloadData()
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
}

extension VenueCouponsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { coupons.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { coupons.isEmpty ? nil : "Your coupons" }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { StoreCouponCopy.explanation }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let coupon = coupons[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = coupon.title
        config.secondaryText = StoreCouponCopy.ownerLine(coupon)
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.numberOfLines = 0
        config.image = UIImage(systemName: coupon.state == "live" ? "ticket.fill" : "ticket")
        config.imageProperties.tintColor = coupon.state == "live" ? Constants.Colors.primary : .systemGray3
        config.textProperties.color = coupon.state == "live" ? .label : .secondaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        openCoupon(coupons[indexPath.row])
    }
}
