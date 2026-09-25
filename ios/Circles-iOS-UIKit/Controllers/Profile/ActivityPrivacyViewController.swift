import UIKit

/// Settings → Privacy → "Who can see my activity".
///
/// A checkbox grid, audience across the top and activity type down the side,
/// that applies to the whole account. Per-item privacy stays the fine-grained
/// control; this only narrows it. Nothing is written until Save is tapped, and
/// a failed load never gets defaults written over it.
final class ActivityPrivacyViewController: BaseTableViewController {

    private enum Section {
        case grid
        case innerCircleEmpty
    }

    private static let gridCell = "ActivityPrivacyRowCell"
    private static let linkCell = "ActivityPrivacyLinkCell"

    /// What the server last confirmed. Nil until the load succeeds.
    private var loaded: ActivityPrivacy?
    /// What the boxes show.
    private var privacy: ActivityPrivacy = .standard
    private var didStartLoading = false
    private var isSaving = false

    private lazy var saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))

    override var loadsDataOnViewDidLoad: Bool { false }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = ActivityPrivacy.Copy.screenTitle
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = saveButton
        // Nothing to pull for: the grid is loaded once and edited in place.
        refreshControl = nil

        tableView.register(ActivityPrivacyRowCell.self, forCellReuseIdentifier: Self.gridCell)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.linkCell)
        tableView.sectionHeaderTopPadding = 8

        NotificationCenter.default.addObserver(self, selector: #selector(innerCircleChanged),
                                               name: .innerCircleDidChange, object: nil)
        InnerCircleManager.shared.primeIfNeeded()
        updateSaveButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The loading alert needs a view in the window, which viewDidLoad
        // doesn't have yet on a push.
        guard !didStartLoading else { return }
        didStartLoading = true
        load()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Load / save

    private func load() {
        let loading = AlertPresenter.showLoading(message: "Loading…", from: self)
        UserService.shared.fetchUserProfile { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let user):
                        let grid = (user.activityPrivacy ?? .standard).normalized
                        self.loaded = grid
                        self.privacy = grid
                        self.hideEmptyState()
                        self.tableView.reloadData()
                    case .failure(let error):
                        // Leave `loaded` nil: Save stays off, and nothing can
                        // write the all-allowed default over a grid we never saw.
                        self.didStartLoading = false
                        self.showEmptyState(message: ActivityPrivacy.Copy.loadFailed)
                        self.showError(error)
                    }
                    self.updateSaveButton()
                }
            }
        }
    }

    @objc private func saveTapped() {
        guard loaded != nil, !isSaving else { return }
        isSaving = true
        updateSaveButton()
        let loading = AlertPresenter.showLoading(message: "Saving…", from: self)
        UserService.shared.updateActivityPrivacy(privacy) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    self.isSaving = false
                    switch result {
                    case .success(let saved):
                        self.loaded = saved
                        self.privacy = saved
                        if let current = AuthService.shared.currentUser {
                            AuthService.shared.updateCurrentUser(current.copy(activityPrivacy: saved))
                        }
                        self.tableView.reloadData()
                        self.showSuccess(ActivityPrivacy.Copy.saved)
                    case .failure(let error):
                        self.showError(error)
                    }
                    self.updateSaveButton()
                }
            }
        }
    }

    private func updateSaveButton() {
        guard let loaded = loaded, !isSaving else {
            saveButton.isEnabled = false
            return
        }
        saveButton.isEnabled = privacy != loaded
    }

    @objc private func innerCircleChanged() {
        // Row summaries and the "empty" row both depend on the list.
        tableView.reloadData()
    }

    // MARK: - Sections

    private var innerCircleIsEmpty: Bool {
        InnerCircleManager.shared.hasLoaded && InnerCircleManager.shared.memberCount == 0
    }

    private var sections: [Section] {
        guard loaded != nil else { return [] }
        return innerCircleIsEmpty ? [.grid, .innerCircleEmpty] : [.grid]
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .grid: return ActivityPrivacyCategory.allCases.count
        case .innerCircleEmpty: return 1
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard sections[section] == .grid else { return nil }
        let header = ActivityPrivacyHeaderView()
        header.onInfo = { [weak self] in
            guard let self = self else { return }
            RelationshipExplainer.present(from: self)
        }
        return header
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section] == .grid ? ActivityPrivacy.Copy.footer : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .grid:
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.gridCell, for: indexPath) as! ActivityPrivacyRowCell
            let category = ActivityPrivacyCategory.allCases[indexPath.row]
            cell.configure(category: category, privacy: privacy, innerCircleIsEmpty: innerCircleIsEmpty)
            cell.onToggle = { [weak self] audience in
                guard let self = self else { return }
                self.privacy = self.privacy.toggled(category: category, audience: audience)
                self.updateSaveButton()
                // The row's own boxes and summary; a Connections tap can flip
                // two boxes at once, so re-derive rather than flip locally.
                if let live = self.tableView.cellForRow(at: indexPath) as? ActivityPrivacyRowCell {
                    live.configure(category: category, privacy: self.privacy, innerCircleIsEmpty: self.innerCircleIsEmpty)
                }
            }
            return cell
        case .innerCircleEmpty:
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.linkCell, for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.image = UIImage(systemName: PrivacyTier.innerCircle.systemIconName)
            config.imageProperties.tintColor = Constants.Colors.primary
            config.text = ActivityPrivacy.Copy.emptyInnerCircleTitle
            config.secondaryText = ActivityPrivacy.Copy.emptyInnerCircleDetail
            config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
            config.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .footnote)
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard sections[indexPath.section] == .innerCircleEmpty else { return }
        navigationController?.pushViewController(InnerCircleListsViewController(), animated: true)
    }
}

// MARK: - Layout shared by header and rows

enum ActivityPrivacyLayout {
    /// Width of each audience column, in the header and in every row, so the
    /// boxes sit under their titles.
    static let columnWidth: CGFloat = 64
    static let horizontalInset: CGFloat = 16
    static let checkboxPointSize: CGFloat = 22

    /// At accessibility text sizes three columns no longer fit beside a
    /// title, so rows stack their boxes vertically with the audience named
    /// beside each, and the header drops its column titles.
    static func stacksVertically(_ traits: UITraitCollection) -> Bool {
        traits.preferredContentSizeCategory.isAccessibilityCategory
    }
}

// MARK: - Header

/// "Activity ⓘ" on the left, the three audience titles over their columns.
final class ActivityPrivacyHeaderView: UIView {

    var onInfo: (() -> Void)?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = ActivityPrivacy.Copy.headerTitle.uppercased()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Constants.Colors.secondaryLabel
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return label
    }()

    private lazy var infoButton: UIButton = {
        let button = UIButton.iconButton(systemName: "info.circle", pointSize: 15)
        button.tintColor = Constants.Colors.primary
        button.accessibilityLabel = "What do these audiences mean?"
        button.addTarget(self, action: #selector(infoTapped), for: .touchUpInside)
        return button
    }()

    private let columnsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .bottom
        stack.spacing = 0
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        let titleStack = UIStackView(arrangedSubviews: [titleLabel, infoButton])
        titleStack.axis = .horizontal
        titleStack.alignment = .center
        titleStack.spacing = 4

        for audience in ActivityAudience.allCases {
            let label = UILabel()
            label.text = audience.title
            label.font = UIFont.preferredFont(forTextStyle: .caption1)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = Constants.Colors.secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 2
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
            label.widthAnchor.constraint(equalToConstant: ActivityPrivacyLayout.columnWidth).isActive = true
            columnsStack.addArrangedSubview(label)
        }

        let row = UIStackView(arrangedSubviews: [titleStack, columnsStack])
        row.axis = .horizontal
        row.alignment = .bottom
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ActivityPrivacyLayout.horizontalInset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ActivityPrivacyLayout.horizontalInset)
        ])
        applyLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyLayout()
    }

    private func applyLayout() {
        columnsStack.isHidden = ActivityPrivacyLayout.stacksVertically(traitCollection)
    }

    @objc private func infoTapped() { onInfo?() }
}

// MARK: - Row

/// One activity type: title and "who sees it" line on the left, a checkbox per
/// audience on the right.
final class ActivityPrivacyRowCell: UITableViewCell {

    var onToggle: ((ActivityAudience) -> Void)?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        return label
    }()

    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private struct Column {
        let audience: ActivityAudience
        let button: UIButton
        let label: UILabel
        let container: UIStackView
        let width: NSLayoutConstraint
    }

    private var columns: [Column] = []
    private let columnsStack = UIStackView()
    private let mainStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        selectionStyle = .none

        let textStack = UIStackView(arrangedSubviews: [titleLabel, summaryLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        columnsStack.spacing = 0
        columnsStack.alignment = .center
        for (index, audience) in ActivityAudience.allCases.enumerated() {
            let column = makeColumn(for: audience, tag: index)
            columns.append(column)
            columnsStack.addArrangedSubview(column.container)
        }

        mainStack.addArrangedSubview(textStack)
        mainStack.addArrangedSubview(columnsStack)
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: ActivityPrivacyLayout.horizontalInset),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -ActivityPrivacyLayout.horizontalInset)
        ])
        applyLayout()
    }

    private func makeColumn(for audience: ActivityAudience, tag: Int) -> Column {
        let button = UIButton.iconButton(systemName: "square", pointSize: ActivityPrivacyLayout.checkboxPointSize)
        // Same symbol configuration for both states, or the box shifts as it
        // toggles. UIButton doesn't cascade `.selected` into combined states:
        // without these, an implied (selected + disabled) box would draw the
        // empty square, and a checked box would flash empty on touch-down.
        let config = UIImage.SymbolConfiguration(pointSize: ActivityPrivacyLayout.checkboxPointSize, weight: .medium)
        let checked = UIImage(systemName: "checkmark.square.fill", withConfiguration: config)
        for state in [[.selected], [.selected, .disabled], [.selected, .highlighted]] as [UIControl.State] {
            button.setImage(checked, for: state)
        }
        button.tintColor = Constants.Colors.primary
        button.tag = tag
        button.addTarget(self, action: #selector(boxTapped(_:)), for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        let label = UILabel()
        label.text = audience.title
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0

        let container = UIStackView(arrangedSubviews: [button, label])
        container.axis = .horizontal
        container.alignment = .center
        container.spacing = 6
        let width = container.widthAnchor.constraint(equalToConstant: ActivityPrivacyLayout.columnWidth)
        return Column(audience: audience, button: button, label: label, container: container, width: width)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            applyLayout()
        }
    }

    private func applyLayout() {
        let vertical = ActivityPrivacyLayout.stacksVertically(traitCollection)
        mainStack.axis = vertical ? .vertical : .horizontal
        mainStack.alignment = vertical ? .fill : .center
        columnsStack.axis = vertical ? .vertical : .horizontal
        columnsStack.alignment = vertical ? .leading : .center
        for column in columns {
            column.label.isHidden = !vertical
            column.width.isActive = !vertical
        }
    }

    func configure(category: ActivityPrivacyCategory, privacy: ActivityPrivacy, innerCircleIsEmpty: Bool) {
        titleLabel.text = category.title
        summaryLabel.text = privacy.summary(for: category, innerCircleIsEmpty: innerCircleIsEmpty)

        for column in columns {
            let checked = privacy.allows(category, column.audience)
            let implied = privacy.isImplied(category, column.audience)
            let button = column.button
            button.isSelected = checked
            // Implied boxes are checked and dimmed: they can't be unchecked
            // while Connections is on. An empty Inner Circle dims too, to
            // say the box reaches nobody yet — but it stays tappable.
            button.isEnabled = !implied
            let reachesNobody = column.audience == .innerCircle && innerCircleIsEmpty
            button.alpha = (implied || reachesNobody) ? 0.4 : 1

            button.accessibilityLabel = "\(category.title), \(column.audience.title)"
            button.accessibilityValue = checked ? "checked" : "unchecked"
            if implied {
                button.accessibilityHint = ActivityPrivacy.Copy.impliedInnerCircleHint
            } else if reachesNobody {
                button.accessibilityHint = ActivityPrivacy.Copy.emptyInnerCircleTitle
            } else {
                button.accessibilityHint = nil
            }
        }
    }

    @objc private func boxTapped(_ sender: UIButton) {
        guard sender.tag < ActivityAudience.allCases.count else { return }
        onToggle?(ActivityAudience.allCases[sender.tag])
    }
}
