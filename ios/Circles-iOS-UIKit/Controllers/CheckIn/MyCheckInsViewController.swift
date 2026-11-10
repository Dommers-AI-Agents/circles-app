import UIKit

/// Every place you've checked in at, newest first, with how many times
/// (Wes, 2026-11-09: the My check-ins next step should sum up your
/// check-ins per place, not open visit tracking). Tapping a row opens the
/// place. Only the viewer's own history.
final class MyCheckInsViewController: BaseViewController {

    private var page: CheckInPlacesPage?

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { MyCheckInsCopy.emptyTitle }
    override var emptyStateActionTitle: String? { NextStep.explore.title }
    override func emptyStateActionTapped() { NextStepNavigator.explore() }

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.register(CheckInPlaceCell.self, forCellReuseIdentifier: CheckInPlaceCell.reuseId)
        table.backgroundColor = .systemGroupedBackground
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 84
        return table
    }()

    private let headerView = UIView()
    private let headlineLabel = UILabel()
    private let recentLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = MyCheckInsCopy.title
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        setupHeader()
        NotificationCenter.default.addObserver(self, selector: #selector(checkInCreated), name: .checkInCreated, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func setupHeader() {
        headlineLabel.font = UIFont.serifBold(26)
        headlineLabel.textColor = Constants.Colors.label
        headlineLabel.numberOfLines = 0
        recentLabel.font = .systemFont(ofSize: 15)
        recentLabel.textColor = .secondaryLabel
        recentLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [headlineLabel, recentLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8)
        ])
    }

    @objc private func checkInCreated() { loadData() }

    override func loadData(completion: (() -> Void)? = nil) {
        CheckInService.shared.getMyCheckInPlaces { [weak self] result in
            DispatchQueue.main.async {
                defer { completion?() }
                guard let self else { return }
                switch result {
                case .success(let page):
                    self.page = page
                    self.render()
                case .failure(let error):
                    // A failed refresh never empties what's already shown
                    if self.page == nil { self.showEmptyState(message: NetworkErrorClassifier.isConnectivityFailure(error) ? "No signal — pull to try again" : self.emptyStateMessage) }
                    else { self.showError(error) }
                }
            }
        }
    }

    private func render() {
        guard let page else { return }
        if page.items.isEmpty {
            tableView.tableHeaderView = nil
            tableView.reloadData()
            showEmptyState()
            return
        }
        hideEmptyState()
        headlineLabel.text = MyCheckInsCopy.headline(total: page.total, places: page.places)
        recentLabel.text = MyCheckInsCopy.recent(page.recent, days: page.recentDays)
        recentLabel.isHidden = recentLabel.text == nil
        let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        let size = headerView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                      withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        headerView.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        tableView.tableHeaderView = headerView
        tableView.reloadData()
    }

    private func open(_ place: CheckInPlaceSummary) {
        let loading = AlertPresenter.showLoading(from: self)
        GlobalPlaceService.shared.getGlobalPlace(id: place.globalPlaceId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let response):
                        self.navigationController?.pushViewController(PlaceDetailViewController(place: response.bestDetailPlace()), animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
}

extension MyCheckInsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { page?.items.count ?? 0 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CheckInPlaceCell.reuseId, for: indexPath) as! CheckInPlaceCell
        if let item = page?.items[indexPath.row] { cell.configure(item) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let item = page?.items[indexPath.row] { open(item) }
    }
}

/// Cover, name, "Checked in 7 times · last Sep 5 · first Jan 5", and a
/// count badge for places you've been to lately.
final class CheckInPlaceCell: UITableViewCell {
    static let reuseId = "CheckInPlaceCell"

    private let coverView = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let countLabel = UILabel()
    private let badgeLabel = InsetLabel()
    private var loadedFor: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 10
        coverView.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.12)
        coverView.tintColor = Constants.Colors.primary
        coverView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.textColor = Constants.Colors.label
        nameLabel.numberOfLines = 2
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 2

        countLabel.font = UIFont.serifBold(24)
        countLabel.textColor = Constants.Colors.primary
        countLabel.textAlignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        badgeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = Constants.Colors.primary
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.clipsToBounds = true
        badgeLabel.textAlignment = .center
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let text = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 3
        let right = UIStackView(arrangedSubviews: [countLabel, badgeLabel])
        right.axis = .vertical
        right.alignment = .trailing
        right.spacing = 4
        let row = UIStackView(arrangedSubviews: [coverView, text, right])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            coverView.widthAnchor.constraint(equalToConstant: 56),
            coverView.heightAnchor.constraint(equalToConstant: 56),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ place: CheckInPlaceSummary) {
        nameLabel.text = place.name
        detailLabel.text = MyCheckInsCopy.detail(for: place)
        countLabel.text = "\(place.count)"
        countLabel.accessibilityLabel = place.count == 1 ? "1 check-in" : "\(place.count) check-ins"
        badgeLabel.text = MyCheckInsCopy.recentBadge(place.recentCount)
        badgeLabel.isHidden = badgeLabel.text == nil
        coverView.image = UIImage(systemName: "mappin.and.ellipse")
        coverView.contentMode = .center
        loadedFor = place.globalPlaceId
        guard let url = place.photoUrl else { return }
        ImageService.shared.loadPlaceImage(for: place.globalPlaceId, from: url) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.loadedFor == place.globalPlaceId, let image else { return }
                self.coverView.image = image
                self.coverView.contentMode = .scaleAspectFill
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadedFor = nil
        coverView.image = nil
    }
}

/// A label with a little room around its text (the "×3 lately" badge)
private final class InsetLabel: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
