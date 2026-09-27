import UIKit

/// Profile › Activity: everything the signed-in user did, in one place —
/// check-ins (private ones too), places added, moments, postcards and
/// Fridge Mail sent, and the day's social actions folded into one line.
/// A month-at-a-glance card sits on top; chips filter the timeline.
///
/// Sits inside the profile's outer scroll view like the grid tabs, so it
/// never scrolls itself: it reports its height through
/// `onContentHeightChanged` and the host sizes the slot. Own profile only.
final class ProfileActivityTabViewController: BaseViewController {
    private(set) var isActiveTab = false
    var onContentHeightChanged: ((CGFloat) -> Void)?

    private let summaryView = ProfileActivitySummaryView()
    private let chipsScroll = UIScrollView()
    private let chipsRow = UIStackView()
    private var chipButtons: [ProfileActivityTimeline.Filter: UIButton] = [:]
    private let tableView = UITableView(frame: .zero, style: .plain)
    private lazy var moreButton = UIButton.secondaryButton(title: "Show more")
    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 15)
        l.textColor = Constants.Colors.secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        l.isHidden = true
        return l
    }()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let stack = UIStackView()
    private var tableHeight: NSLayoutConstraint?
    private var contentSizeObservation: NSKeyValueObservation?

    private var filter: ProfileActivityTimeline.Filter = .all
    private var items: [OwnActivityItem] = []
    private var sections: [ProfileActivityTimeline.DaySection] = []
    private var nextCursor: String?
    private var hasMore = false
    private var isLoading = false
    private var summary: OwnActivitySummary?
    private var lastLoadedAt: Date?
    private var expandedDigests: Set<String> = []

    override var loadsDataOnViewDidLoad: Bool { false }
    override var reloadsDataOnAppear: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildLayout()
        summaryView.onTapCount = { [weak self] filter in self?.select(filter) }
        summaryView.onShare = { [weak self] in self?.shareRecap() }
        contentSizeObservation = tableView.observe(\.contentSize, options: [.new]) { [weak self] table, _ in
            DispatchQueue.main.async { self?.tableDidResize(table.contentSize.height) }
        }
    }

    private func buildLayout() {
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.small
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let summaryWrap = UIView()
        summaryWrap.addSubview(summaryView)
        NSLayoutConstraint.activate([
            summaryView.topAnchor.constraint(equalTo: summaryWrap.topAnchor, constant: Constants.Spacing.small),
            summaryView.leadingAnchor.constraint(equalTo: summaryWrap.leadingAnchor, constant: Constants.Spacing.medium),
            summaryView.trailingAnchor.constraint(equalTo: summaryWrap.trailingAnchor, constant: -Constants.Spacing.medium),
            summaryView.bottomAnchor.constraint(equalTo: summaryWrap.bottomAnchor)
        ])
        summaryView.configure(with: nil)

        chipsScroll.showsHorizontalScrollIndicator = false
        chipsRow.axis = .horizontal
        chipsRow.spacing = 8
        chipsRow.translatesAutoresizingMaskIntoConstraints = false
        chipsScroll.addSubview(chipsRow)
        for filter in ProfileActivityTimeline.Filter.allCases {
            let button = UIButton.pillButton(title: filter.title)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
            button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
            button.layer.cornerRadius = 16
            button.tag = ProfileActivityTimeline.Filter.allCases.firstIndex(of: filter) ?? 0
            button.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chipsRow.addArrangedSubview(button)
            chipButtons[filter] = button
        }
        NSLayoutConstraint.activate([
            chipsRow.topAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.topAnchor),
            chipsRow.bottomAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.bottomAnchor),
            chipsRow.leadingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.leadingAnchor, constant: Constants.Spacing.medium),
            chipsRow.trailingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.trailingAnchor, constant: -Constants.Spacing.medium),
            chipsRow.heightAnchor.constraint(equalTo: chipsScroll.frameLayoutGuide.heightAnchor),
            chipsScroll.heightAnchor.constraint(equalToConstant: 34)
        ])
        paintChips()

        tableView.isScrollEnabled = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.sectionHeaderTopPadding = 0
        tableView.register(ProfileActivityRowCell.self, forCellReuseIdentifier: ProfileActivityRowCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableHeight = tableView.heightAnchor.constraint(equalToConstant: 0)
        tableHeight?.isActive = true

        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        let moreWrap = UIView()
        moreWrap.addSubview(moreButton)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            moreButton.topAnchor.constraint(equalTo: moreWrap.topAnchor),
            moreButton.bottomAnchor.constraint(equalTo: moreWrap.bottomAnchor),
            moreButton.leadingAnchor.constraint(equalTo: moreWrap.leadingAnchor, constant: Constants.Spacing.medium),
            moreButton.trailingAnchor.constraint(equalTo: moreWrap.trailingAnchor, constant: -Constants.Spacing.medium)
        ])
        moreWrap.isHidden = true

        let statusWrap = UIView()
        statusWrap.addSubview(emptyLabel)
        statusWrap.addSubview(spinner)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        NSLayoutConstraint.activate([
            statusWrap.heightAnchor.constraint(equalToConstant: 48),
            emptyLabel.centerXAnchor.constraint(equalTo: statusWrap.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: statusWrap.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: statusWrap.leadingAnchor, constant: Constants.Spacing.large),
            spinner.centerXAnchor.constraint(equalTo: statusWrap.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: statusWrap.centerYAnchor)
        ])

        [summaryWrap, chipsScroll, tableView, moreWrap, statusWrap].forEach { stack.addArrangedSubview($0) }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
        moreButton.superview?.tag = 1
    }

    private var moreWrap: UIView? { stack.arrangedSubviews.first { $0.tag == 1 } }

    // MARK: - Host contract

    func setActive(_ active: Bool) {
        isActiveTab = active
        view.isHidden = !active
        guard active else { return }
        if lastLoadedAt == nil || Date().timeIntervalSince(lastLoadedAt!) > 60 {
            reload()
        } else {
            reportHeight()
        }
    }

    private func reportHeight() {
        view.layoutIfNeeded()
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let size = stack.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                 withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        onContentHeightChanged?(max(size.height, 120))
    }

    private func tableDidResize(_ height: CGFloat) {
        guard abs((tableHeight?.constant ?? 0) - height) >= 1 else { return }
        tableHeight?.constant = height
        reportHeight()
    }

    // MARK: - Loading

    private func reload() {
        lastLoadedAt = Date()
        loadSummary()
        loadPage(reset: true)
    }

    private func loadSummary() {
        ProfileActivityService.shared.fetchSummary { [weak self] result in
            guard let self else { return }
            if case .success(let summary) = result {
                self.summary = summary
                self.summaryView.configure(with: summary)
                self.reportHeight()
            }
        }
    }

    private func loadPage(reset: Bool) {
        guard !isLoading else { return }
        isLoading = true
        if reset {
            nextCursor = nil
            spinner.startAnimating()
            emptyLabel.isHidden = true
        }
        moreButton.isEnabled = false
        let requestedFilter = filter
        ProfileActivityService.shared.fetchPage(filter: requestedFilter, cursor: reset ? nil : nextCursor) { [weak self] result in
            guard let self, requestedFilter == self.filter else { return }
            self.isLoading = false
            self.spinner.stopAnimating()
            self.moreButton.isEnabled = true
            switch result {
            case .success(let page):
                self.items = reset ? page.items : self.items + page.items
                self.nextCursor = page.nextCursor
                self.hasMore = page.hasMore && page.nextCursor != nil
                self.render()
            case .failure(let error):
                Logger.debug("❌ Activity tab: \(error)")
                if self.items.isEmpty {
                    self.emptyLabel.text = "Couldn't load your activity. Pull to refresh to try again."
                    self.emptyLabel.isHidden = false
                }
                self.reportHeight()
            }
        }
    }

    private func render() {
        sections = ProfileActivityTimeline.sections(from: items)
        tableView.reloadData()
        moreWrap?.isHidden = !hasMore
        if items.isEmpty {
            emptyLabel.text = filter.emptyMessage
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
        reportHeight()
    }

    // MARK: - Filters

    private func select(_ next: ProfileActivityTimeline.Filter) {
        guard next != filter || items.isEmpty else { return }
        filter = next
        paintChips()
        items = []
        sections = []
        expandedDigests = []
        tableView.reloadData()
        loadPage(reset: true)
    }

    private func paintChips() {
        for (f, button) in chipButtons {
            let on = f == filter
            button.backgroundColor = on ? Constants.Colors.primary : Constants.Colors.secondaryBackground
            button.setTitleColor(on ? .white : Constants.Colors.label, for: .normal)
            button.accessibilityTraits = on ? [.button, .selected] : .button
        }
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard ProfileActivityTimeline.Filter.allCases.indices.contains(sender.tag) else { return }
        select(ProfileActivityTimeline.Filter.allCases[sender.tag])
    }

    @objc private func moreTapped() { loadPage(reset: false) }

    // MARK: - Share

    private func shareRecap() {
        guard let summary else { return }
        let fullName = AuthService.shared.currentUser?.displayName ?? ""
        let name = fullName.split(separator: " ").first.map(String.init) ?? "My"
        let text = ProfileActivityTimeline.recapText(summary, name: name)
        let image = summaryView.renderImage()
        let share = UIActivityViewController(activityItems: [image, text], applicationActivities: nil)
        if let popover = share.popoverPresentationController {
            popover.sourceView = summaryView
            popover.sourceRect = summaryView.bounds
        }
        present(share, animated: true)
    }

    // MARK: - Taps

    private func open(_ item: OwnActivityItem) {
        switch ProfileActivityTimeline.Kind(category: item.category) {
        case .checkIn, .place:
            if let placeId = item.placeId ?? (item.targetType == "place" ? item.targetId : nil) { openPlace(id: placeId) }
        case .moment:
            if let videoId = item.targetId { openMoment(id: videoId) }
        case .sent:
            NotificationCenter.default.post(name: .navigateToHomeWidget, object: item.type == "fridgemail_sent" ? "fridgemail" : "postcard")
        case .social:
            if let placeId = item.placeId ?? (item.targetType == "place" ? item.targetId : nil) { openPlace(id: placeId) }
            else if item.targetType == "video", let videoId = item.targetId { openMoment(id: videoId) }
        case .other:
            break
        }
    }

    private func openPlace(id: String) {
        let loading = AlertPresenter.showLoading(message: "Loading place...", from: self)
        APIService.shared.request(endpoint: "places/\(id)", method: .get) { [weak self] (result: Result<PlaceResponse, APIError>) in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let response):
                        let detail = PlaceDetailViewController(place: response.place, circle: nil)
                        self.navigationController?.pushViewController(detail, animated: true)
                    case .failure:
                        self.showError("That place isn't available any more.")
                    }
                }
            }
        }
    }

    private func openMoment(id: String) {
        let loading = AlertPresenter.showLoading(message: "Loading moment...", from: self)
        APIService.shared.request(endpoint: "videos/\(id)", method: .get) { [weak self] (result: Result<PlaceVideoResponse, APIError>) in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let response):
                        let reels = VideoReelsViewController(reels: [response.data], startIndex: 0)
                        reels.modalPresentationStyle = .fullScreen
                        self.present(reels, animated: true)
                    case .failure:
                        self.showError("That moment isn't available any more.")
                    }
                }
            }
        }
    }
}

// MARK: - Table

extension ProfileActivityTabViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows(in: section).count
    }

    /// A digest the user expanded shows its rows in place.
    private func rows(in section: Int) -> [ProfileActivityTimeline.Row] {
        sections[section].rows.flatMap { row -> [ProfileActivityTimeline.Row] in
            if case .socialDigest(let day, let items) = row, expandedDigests.contains(day) {
                return [row] + items.map { .single($0) }
            }
            return [row]
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        label.textColor = Constants.Colors.secondaryLabel
        label.text = sections[section].title.uppercased()
        let wrap = UIView()
        wrap.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: Constants.Spacing.medium),
            label.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -Constants.Spacing.medium),
            label.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -2)
        ])
        return wrap
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 30 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ProfileActivityRowCell.reuseIdentifier, for: indexPath) as! ProfileActivityRowCell
        switch rows(in: indexPath.section)[indexPath.row] {
        case .single(let item): cell.configure(item: item)
        case .socialDigest(_, let items): cell.configure(digest: items)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch rows(in: indexPath.section)[indexPath.row] {
        case .single(let item):
            open(item)
        case .socialDigest(let day, _):
            if expandedDigests.contains(day) { expandedDigests.remove(day) } else { expandedDigests.insert(day) }
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .fade)
        }
    }
}
