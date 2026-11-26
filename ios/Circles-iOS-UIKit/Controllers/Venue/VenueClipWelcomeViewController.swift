import UIKit

/// Manage Store → App Clip screens (Wes, 2026-11-26): what a customer sees
/// after tapping Open on the store's App Clip card. Every store starts with
/// the same screens filled from what it already has; the owner can change
/// the words, which rows show, points and Wallet, and the sign-in photo.
/// Each change saves at once and shows at the next scan.
final class VenueClipWelcomeViewController: BaseViewController {

    private let venueId: String
    private var settings: ClipWelcomeSettings?

    private enum Section: Int, CaseIterable {
        case words, rows, rewards, photo
        var title: String {
            switch self {
            case .words: return "Words"
            case .rows: return "What staying connected brings"
            case .rewards: return "Points & Apple Wallet"
            case .photo: return "Sign-in screen photo"
            }
        }
    }

    private enum WordsRow: Int, CaseIterable { case shortName, welcomeLine, doneLine }

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
        title = "App Clip Screens"
        navigationItem.largeTitleDisplayMode = .never
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: "SwitchCell")
        view.addSubview(tableView)
        view.sendSubviewToBack(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        tableView.tableHeaderView = headerView()
    }

    override func loadData(completion: (() -> Void)? = nil) {
        ClipWelcomeService.shared.load(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let settings):
                    self.settings = settings
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showErrorWithRetry(error) { self.loadData(completion: completion) }
                }
                completion?()
            }
        }
    }

    private func headerView() -> UIView {
        let label = UILabel()
        label.text = "When a customer scans your window code and taps Open, they see Welcome, then sign-in, then \u{201C}You\u{2019}re connected.\u{201D} Changes show at their next scan."
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 84))
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    // MARK: - Saving

    private func save(_ fields: [String: Any]) {
        ClipWelcomeService.shared.update(venueId: venueId, fields) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let settings):
                    self.settings = settings
                case .failure(let error):
                    self.showError(error.serverMessage ?? error.localizedDescription)
                }
                self.tableView.reloadData()
            }
        }
    }

    private func editText(title: String, message: String, key: String, current: String?) {
        showTextInput(title: title, message: message, initialText: current) { [weak self] text in
            guard let text else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.save([key: trimmed.isEmpty ? NSNull() : trimmed])
        }
    }

    /// Rows shown now, in order (the owner's list, else every row the store can back)
    private var shownRows: [String] {
        settings?.overrides.rows ?? settings?.rowKinds ?? []
    }

    private func setRow(_ kind: String, on: Bool) {
        guard let settings else { return }
        var rows = shownRows
        if on, !rows.contains(kind) {
            rows = settings.rowKinds.filter { rows.contains($0) || $0 == kind }
        } else if !on {
            rows.removeAll { $0 == kind }
        }
        save(["rows": rows])
    }

    private static func rowTitle(_ kind: String) -> String {
        switch kind {
        case "rewards": return "Rewards"
        case "menu": return "See the menu"
        case "specials": return "Specials"
        case "events": return "Events"
        case "announcements": return "Announcements"
        default: return kind.capitalized
        }
    }

    private func openPhotoPicker() {
        guard let settings, !settings.photos.isEmpty else {
            showError("Add photos to your page first (Manage Store \u{2192} Photos).")
            return
        }
        let current = settings.overrides.connectPhotoUrl ?? settings.experience.connect.photoUrl
        let picker = ClipPhotoPickerViewController(photos: settings.photos, selected: current) { [weak self] url in
            self?.save(["connectPhotoUrl": url ?? NSNull()])
        }
        navigationController?.pushViewController(picker, animated: true)
    }
}

extension VenueClipWelcomeViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { settings == nil ? 0 : Section.allCases.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let settings else { return nil }
        switch Section(rawValue: section) {
        case .rows:
            return "Each row tells customers what they\u{2019}ll get. Rows never show counts or dates."
        case .rewards:
            return settings.rewardsLive
                ? "Points on the screens and the Apple Wallet card. Turn them off if you\u{2019}d rather not mention points."
                : "These turn on when your rewards are live."
        case .photo:
            return "The photo behind \u{201C}Stay connected.\u{201D} By default it\u{2019}s your second photo."
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let settings else { return 0 }
        switch Section(rawValue: section) {
        case .words: return WordsRow.allCases.count
        case .rows: return settings.rowKinds.count
        case .rewards: return 2
        case .photo: return 1
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let settings, let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }
        switch section {
        case .words:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var config = UIListContentConfiguration.subtitleCell()
            switch WordsRow(rawValue: indexPath.row)! {
            case .shortName:
                config.text = "Short name"
                config.secondaryText = "\u{201C}\(settings.experience.welcome.button)\u{201D}"
            case .welcomeLine:
                config.text = "Welcome line"
                config.secondaryText = settings.experience.welcome.line
            case .doneLine:
                config.text = "\u{201C}You\u{2019}re connected\u{201D} line"
                config.secondaryText = settings.experience.done.line
            }
            config.secondaryTextProperties.color = .secondaryLabel
            config.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            return cell

        case .rows:
            let kind = settings.rowKinds[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchTableViewCell
            let unavailable = kind == "rewards" && !settings.rewardsLive
            cell.configure(title: Self.rowTitle(kind) + (unavailable ? " (when rewards are live)" : ""),
                           isOn: shownRows.contains(kind)) { [weak self] on in self?.setRow(kind, on: on) }
            return cell

        case .rewards:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchTableViewCell
            if indexPath.row == 0 {
                cell.configure(title: "Show points", isOn: settings.overrides.showRewards != false) { [weak self] on in
                    self?.save(["showRewards": on])
                }
            } else {
                cell.configure(title: "Offer the Apple Wallet card", isOn: settings.overrides.showWallet != false) { [weak self] on in
                    self?.save(["showWallet": on])
                }
            }
            cell.contentView.alpha = settings.rewardsLive ? 1 : 0.5
            return cell

        case .photo:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var config = UIListContentConfiguration.subtitleCell()
            config.text = "Choose the photo"
            config.secondaryText = settings.overrides.connectPhotoUrl == nil ? "Automatic" : "Your pick"
            config.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let settings, let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .words:
            switch WordsRow(rawValue: indexPath.row)! {
            case .shortName:
                editText(title: "Short name", message: "Used on the buttons and in short lines, up to 24 letters. Empty uses your store\u{2019}s name.",
                         key: "shortName", current: settings.overrides.shortName ?? settings.experience.shortName)
            case .welcomeLine:
                editText(title: "Welcome line", message: "Under \u{201C}Welcome to \(settings.experience.welcome.title)\u{201D}. Empty uses the standard line.",
                         key: "welcomeLine", current: settings.overrides.welcomeLine ?? settings.experience.welcome.line)
            case .doneLine:
                editText(title: "\u{201C}You\u{2019}re connected\u{201D} line", message: "The last screen. Empty uses the standard line.",
                         key: "doneLine", current: settings.overrides.doneLine ?? settings.experience.done.line)
            }
        case .photo:
            openPhotoPicker()
        default:
            break
        }
    }
}

/// The store's photos in a grid; tap one to put it behind the sign-in screen
private final class ClipPhotoPickerViewController: BaseViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private let photos: [String]
    private let selected: String?
    private let onPick: (String?) -> Void
    private lazy var collection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        return view
    }()

    init(photos: [String], selected: String?, onPick: @escaping (String?) -> Void) {
        self.photos = photos
        self.selected = selected
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var loadsDataOnViewDidLoad: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sign-in Photo"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Automatic", style: .plain, target: self, action: #selector(automaticTapped))
        collection.dataSource = self
        collection.delegate = self
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "Photo")
        view.addSubview(collection)
        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            collection.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            collection.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            collection.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            let side = floor((collection.bounds.width - 12) / 3)
            layout.itemSize = CGSize(width: side, height: side * 1.4)
        }
    }

    @objc private func automaticTapped() {
        onPick(nil)
        navigationController?.popViewController(animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { photos.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Photo", for: indexPath)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let image = UIImageView(frame: cell.contentView.bounds)
        image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.cornerRadius = 8
        image.backgroundColor = .secondarySystemBackground
        let url = photos[indexPath.item]
        if url == selected {
            image.layer.borderWidth = 4
            image.layer.borderColor = Constants.Colors.primary.cgColor
        }
        cell.contentView.addSubview(image)
        ImageService.shared.loadImage(from: url) { loaded in
            DispatchQueue.main.async { image.image = loaded }
        }
        cell.accessibilityLabel = url == selected ? "Photo \(indexPath.item + 1), chosen" : "Photo \(indexPath.item + 1)"
        cell.isAccessibilityElement = true
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onPick(photos[indexPath.item])
        navigationController?.popViewController(animated: true)
    }
}
