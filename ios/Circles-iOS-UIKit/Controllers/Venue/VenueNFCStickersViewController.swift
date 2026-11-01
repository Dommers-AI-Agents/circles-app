import UIKit

/// Manage Store → NFC stickers (2026-11-01). The owner names a sticker
/// ("Table 7"), holds the phone to a blank NFC sticker, and the store's
/// window link with that sticker's tag is written onto it. A customer's tap
/// opens the store's App Clip card (or the app), and each sticker counts its
/// own taps. Free for every store, like the window sticker.
class VenueNFCStickersViewController: BaseViewController {

    private let venueId: String
    private let venueName: String
    private var stickers: [NFCSticker] = []
    private var windowUrl: String?

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        "No NFC stickers yet.\nTap + to name one, like \u{201C}Table 7,\u{201D} then hold your iPhone to a blank NFC sticker."
    }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 56
        return table
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
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
        title = "NFC Stickers"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped)),
            UIBarButtonItem(image: UIImage(systemName: "wave.3.right"), style: .plain, target: self, action: #selector(checkTapped))
        ]
        navigationItem.rightBarButtonItems?.last?.accessibilityLabel = "Check a sticker"

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StickerCell")

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
        RewardsService.shared.listNFCStickers(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let data):
                    self.stickers = data.stickers
                    self.windowUrl = data.windowUrl
                    self.tableView.reloadData()
                    self.stickers.isEmpty ? self.showEmptyState() : self.hideEmptyState()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Add + write

    @objc private func addTapped() {
        guard NFCStickerSession.isAvailable else { return showError(NFCStickerSession.Failure.unavailable) }
        AlertPresenter.showTextInput(
            title: "Name this sticker",
            message: "Where will it go? You'll see its taps under this name.",
            placeholder: "Table 7",
            initialText: "Table \(stickers.count + 1)",
            autocapitalization: .words,
            confirmTitle: "Next",
            from: self
        ) { [weak self] text in
            let label = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let self, !label.isEmpty else { return }
            self.create(label: label)
        }
    }

    private func create(label: String) {
        let loading = AlertPresenter.showLoading(from: self)
        RewardsService.shared.createNFCSticker(venueId: venueId, label: label) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let sticker):
                        self.stickers.append(sticker)
                        self.tableView.reloadData()
                        self.hideEmptyState()
                        self.write(sticker)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func write(_ sticker: NFCSticker) {
        guard let url = URL(string: sticker.url) else { return }
        NFCStickerSession.start(.write(url), prompt: "Hold the top of your iPhone to the \u{201C}\(sticker.label)\u{201D} sticker.") { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                RewardsService.shared.markNFCStickerWritten(venueId: self.venueId, tag: sticker.tag, locked: false) { _ in
                    DispatchQueue.main.async { self.loadData() }
                }
                AlertPresenter.showSuccess(
                    title: "\u{201C}\(sticker.label)\u{201D} is ready",
                    message: "Tap it with any iPhone to see your store's card. Want it permanent? Tap the sticker's row, then Lock.",
                    from: self)
            case .failure(.cancelled):
                break
            case .failure(let failure):
                self.showError(failure)
            }
        }
    }

    private func lock(_ sticker: NFCSticker) {
        guard let url = URL(string: sticker.url) else { return }
        AlertPresenter.showConfirmation(
            title: "Lock this sticker for good?",
            message: "A locked sticker can never be changed or erased, so nobody can swap your link for theirs. Only the sticker holding \u{201C}\(sticker.label)\u{201D}'s link gets locked.",
            confirmTitle: "Lock",
            isDestructive: true,
            from: self
        ) { [weak self] in
            NFCStickerSession.start(.lock(expected: url), prompt: "Hold your iPhone to the \u{201C}\(sticker.label)\u{201D} sticker to lock it.") { result in
                guard let self else { return }
                switch result {
                case .success:
                    RewardsService.shared.markNFCStickerWritten(venueId: self.venueId, tag: sticker.tag, locked: true) { _ in
                        DispatchQueue.main.async { self.loadData() }
                    }
                case .failure(.cancelled):
                    break
                case .failure(let failure):
                    self.showError(failure)
                }
            }
        }
    }

    // MARK: - Check a sticker

    @objc private func checkTapped() {
        NFCStickerSession.start(.read, prompt: "Hold your iPhone to a sticker to see what's on it.") { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.read(let link)):
                self.explain(link)
            case .success:
                break
            case .failure(.cancelled):
                break
            case .failure(let failure):
                self.showError(failure)
            }
        }
    }

    private func explain(_ link: String?) {
        guard let link else {
            return AlertPresenter.showInfo(title: "Blank sticker", message: "Nothing is written on it yet. Tap + to write one.", from: self)
        }
        let known = Set(stickers.map(\.tag))
        switch NFCStickerLink.match(link, windowUrl: windowUrl, knownTags: known) {
        case .sticker(let tag):
            let sticker = stickers.first { $0.tag == tag }
            AlertPresenter.showInfo(
                title: "\u{201C}\(sticker?.label ?? tag)\u{201D}",
                message: "This is your sticker. Taps open \(venueName)'s card and count here.", from: self)
        case .removedTag:
            AlertPresenter.showInfo(
                title: "A removed sticker",
                message: "It still opens \(venueName), but its taps aren't counted any more. Write it again to give it a name here.", from: self)
        case .windowLink:
            AlertPresenter.showInfo(
                title: "Your window link",
                message: "It opens \(venueName), but it isn't one of the named stickers, so taps aren't counted here.", from: self)
        case .otherStore:
            AlertPresenter.showInfo(title: "Another store's sticker", message: "This sticker opens a different FavCircles store.", from: self)
        case .other:
            AlertPresenter.showInfo(title: "Not a FavCircles sticker", message: link, from: self)
        }
    }

    // MARK: - Row actions

    private func showActions(for sticker: NFCSticker, from cell: UIView?) {
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = [
            ("Write another sticker like this", .default, { [weak self] in self?.write(sticker) })
        ]
        if sticker.writtenAt != nil {
            actions.append(("Lock a sticker\u{2026}", .default, { [weak self] in self?.lock(sticker) }))
        }
        actions += [
            ("Rename", .default, { [weak self] in self?.rename(sticker) }),
            ("Copy link", .default, { UIPasteboard.general.string = sticker.url }),
            ("Remove", .destructive, { [weak self] in self?.remove(sticker) })
        ]
        AlertPresenter.showActionSheet(title: sticker.label, message: sticker.url, actions: actions, from: self, sourceView: cell)
    }

    private func rename(_ sticker: NFCSticker) {
        AlertPresenter.showTextInput(title: "Rename sticker", initialText: sticker.label, autocapitalization: .words,
                                     confirmTitle: "Save", from: self) { [weak self] text in
            let label = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let self, !label.isEmpty, label != sticker.label else { return }
            RewardsService.shared.renameNFCSticker(venueId: self.venueId, tag: sticker.tag, label: label) { result in
                DispatchQueue.main.async {
                    if case .failure(let error) = result { self.showError(error) }
                    self.loadData()
                }
            }
        }
    }

    private func remove(_ sticker: NFCSticker) {
        AlertPresenter.showConfirmation(
            title: "Remove \u{201C}\(sticker.label)\u{201D}?",
            message: "The sticker itself keeps opening \(venueName); its taps just stop being counted here.",
            confirmTitle: "Remove",
            isDestructive: true,
            from: self
        ) { [weak self] in
            guard let self else { return }
            RewardsService.shared.deleteNFCSticker(venueId: self.venueId, tag: sticker.tag) { result in
                DispatchQueue.main.async {
                    if case .failure(let error) = result { self.showError(error) }
                    self.loadData()
                }
            }
        }
    }
}

// MARK: - Table
extension VenueNFCStickersViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        stickers.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard !stickers.isEmpty else { return nil }
        let device = NFCStickerSession.isAvailable ? "" : " Writing needs an iPhone; this device has no NFC."
        return "Each sticker holds your window link plus its own name, so a tap opens \(venueName)'s card and counts here. Use NTAG213/215/216 stickers; on metal, use on-metal tags.\(device)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StickerCell", for: indexPath)
        let sticker = stickers[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = sticker.label
        config.secondaryText = NFCStickerLink.tapsLine(
            taps: sticker.taps,
            lastTap: sticker.lastTapAt.flatMap { Self.isoFormatter.date(from: $0) },
            written: sticker.writtenAt != nil,
            locked: sticker.locked == true)
        config.secondaryTextProperties.color = .secondaryLabel
        config.image = UIImage(systemName: sticker.locked == true ? "lock.circle" : "wave.3.right.circle")
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showActions(for: stickers[indexPath.row], from: tableView.cellForRow(at: indexPath))
    }
}
