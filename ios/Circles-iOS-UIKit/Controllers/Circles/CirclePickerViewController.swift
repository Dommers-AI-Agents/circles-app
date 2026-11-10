import UIKit

/// Pick a circle (Add Place, save from map/chat/place page). Inset-grouped
/// rows on the sheet's own background, "New Circle" first when the caller can
/// make one, search only once there are enough circles to need it.
class CirclePickerViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private enum Section: Int, CaseIterable { case create, circles }

    // MARK: - Properties
    private let circles: [Circle]
    private var filteredCircles: [Circle]
    var onCircleSelected: ((Circle) -> Void)?
    /// When nil the sheet offers no "New Circle" row (a caller that can't
    /// make one used to show a button that only closed the sheet)
    var onCreateNewCircle: (() -> Void)?
    /// Sheet title; callers adding a specific place can say so.
    var pickerTitle = "Select Circle"
    /// When set, a card above the list shows the place being added
    /// (name + address), so the sheet says what it's for.
    var placeName: String?
    var placeAddress: String?

    // MARK: - UI Elements
    private lazy var searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search circles"
        return searchController
    }()

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.sectionHeaderTopPadding = 8
        return tableView
    }()

    private var showsCreate: Bool { onCreateNewCircle != nil && (searchController.searchBar.text ?? "").isEmpty }

    // MARK: - Initialization
    init(circles: [Circle]) {
        self.circles = circles
        self.filteredCircles = circles
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
    }

    // MARK: - UI Setup
    private func setupUI() {
        // The sheet's own (glass) background shows through; grouped elsewhere
        if #available(iOS 26.0, *) {
            view.backgroundColor = .clear
        } else {
            view.backgroundColor = .systemGroupedBackground
        }
        title = pickerTitle
        navigationItem.largeTitleDisplayMode = .never

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(cancelButtonTapped)
        )

        // What a circle is, for someone adding their first places (Wes, 2026-10-29)
        let info = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain,
                                   target: self, action: #selector(infoButtonTapped))
        info.accessibilityLabel = "What is a circle?"
        navigationItem.rightBarButtonItem = info

        if CirclePickerRows.showsSearch(circleCount: circles.count) {
            navigationItem.searchController = searchController
            navigationItem.hidesSearchBarWhenScrolling = false
            definesPresentationContext = true
        }

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CirclePickerCell.self, forCellReuseIdentifier: CirclePickerCell.reuseId)
        tableView.register(CirclePickerCreateCell.self, forCellReuseIdentifier: CirclePickerCreateCell.reuseId)
        tableView.tableHeaderView = makePlaceHeader()
    }

    /// "📍 Ilios Crafted Greek / 123 Main St · Choose a circle for it." —
    /// or, before any place is chosen (Home's Add Place), why a circle comes
    /// first (Wes, 2026-11-09)
    private func makePlaceHeader() -> UIView? {
        guard let name = placeName, !name.isEmpty else {
            return CirclePickerHeaderView.make(headline: CirclePickerCopy.headline(forMove: false),
                                               explanation: CirclePickerCopy.explanation(forMove: false, circleCount: circles.count),
                                               width: view.bounds.width)
        }
        let icon = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 20, weight: .bold)
        nameLabel.textColor = Constants.Colors.label
        nameLabel.numberOfLines = 2

        let addressLabel = UILabel()
        addressLabel.text = placeAddress
        addressLabel.font = .systemFont(ofSize: 14)
        addressLabel.textColor = Constants.Colors.secondaryLabel
        addressLabel.numberOfLines = 2
        addressLabel.isHidden = (placeAddress ?? "").isEmpty

        let promptLabel = UILabel()
        promptLabel.text = CirclePickerCopy.explanation(forMove: false, circleCount: circles.count)
        promptLabel.font = .systemFont(ofSize: 14)
        promptLabel.textColor = Constants.Colors.secondaryLabel
        promptLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [nameLabel, addressLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [icon, textStack])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center

        let stack = UIStackView(arrangedSubviews: [row, promptLabel])
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.medium
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: Constants.Spacing.small),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -Constants.Spacing.small)
        ])
        let width = view.bounds.width
        let size = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        header.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        return header
    }
    
    // MARK: - Actions
    @objc private func infoButtonTapped() {
        AlertPresenter.showInfo(title: CirclePickerCopy.infoTitle, message: CirclePickerCopy.info, from: self)
    }

    @objc private func cancelButtonTapped() {
        searchController.isActive = false
        dismiss(animated: true)
    }

    @objc private func createNewButtonTapped() {
        searchController.isActive = false
        dismiss(animated: true) { [weak self] in
            self?.onCreateNewCircle?()
        }
    }
}

// MARK: - UITableViewDataSource
extension CirclePickerViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .create: return showsCreate ? 1 : 0
        case .circles: return filteredCircles.count
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if Section(rawValue: indexPath.section) == .create {
            return tableView.dequeueReusableCell(withIdentifier: CirclePickerCreateCell.reuseId, for: indexPath)
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: CirclePickerCell.reuseId, for: indexPath) as! CirclePickerCell
        cell.configure(with: filteredCircles[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard Section(rawValue: section) == .circles, !filteredCircles.isEmpty else { return nil }
        return "Your circles"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .circles, filteredCircles.isEmpty, !circles.isEmpty else { return nil }
        return "No circles match."
    }
}

// MARK: - UISearchResultsUpdating
extension CirclePickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        filteredCircles = CirclePickerRows.filter(circles, query: searchController.searchBar.text ?? "")
        tableView.reloadData()
    }
}

// MARK: - UITableViewDelegate
extension CirclePickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if Section(rawValue: indexPath.section) == .create {
            createNewButtonTapped()
            return
        }
        guard indexPath.row < filteredCircles.count else { return }
        let circle = filteredCircles[indexPath.row]
        // Dismissing while the search controller is active first tears down the
        // search presentation, which would swallow the sheet dismissal
        searchController.isActive = false
        dismiss(animated: true) { [weak self] in
            self?.onCircleSelected?(circle)
        }
    }
}

// MARK: - CirclePickerCell
/// Cover photo, name, "3 places · Private". Self-sizing, so nothing clips.
class CirclePickerCell: UITableViewCell {
    static let reuseId = "CirclePickerCell"
    private var imageURL: String?

    private let coverView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.tintColor = Constants.Colors.primary
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Constants.Colors.secondaryLabel
        return label
    }()

    private let privacyIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote)
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        let detailRow = UIStackView(arrangedSubviews: [privacyIcon, detailLabel])
        detailRow.spacing = 4
        detailRow.alignment = .center
        let text = UIStackView(arrangedSubviews: [nameLabel, detailRow])
        text.axis = .vertical
        text.spacing = 2
        text.alignment = .leading
        let row = UIStackView(arrangedSubviews: [coverView, text])
        row.spacing = 14
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            coverView.widthAnchor.constraint(equalToConstant: 52),
            coverView.heightAnchor.constraint(equalToConstant: 52),
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 2),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -2),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageURL = nil
        coverView.image = nil
    }

    func configure(with circle: Circle) {
        nameLabel.text = circle.name
        // The circle list sends placesCount, not the ids, so prefer it
        let placeCount = circle.placesCount ?? circle.places?.count ?? 0
        detailLabel.text = CirclePickerRows.detail(placeCount: placeCount, privacy: circle.privacy)
        privacyIcon.image = circle.privacy.tier.map { UIImage(systemName: $0.systemIconName) } ?? nil
        privacyIcon.isHidden = privacyIcon.image == nil

        if let cover = circle.coverImage, !cover.isEmpty {
            imageURL = cover
            coverView.contentMode = .scaleAspectFill
            ImageService.shared.loadImage(from: cover) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self, self.imageURL == cover else { return }
                    self.coverView.image = image
                }
            }
        } else {
            coverView.contentMode = .center
            coverView.image = UIImage(systemName: "circle.grid.2x2.fill",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        }
    }
}

/// The first row: start a new circle
final class CirclePickerCreateCell: UITableViewCell {
    static let reuseId = "CirclePickerCreateCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let tile = UIImageView(image: UIImage(systemName: "plus",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)))
        tile.contentMode = .center
        tile.tintColor = .white
        tile.backgroundColor = Constants.Colors.primary
        tile.layer.cornerRadius = 12
        tile.layer.cornerCurve = .continuous
        tile.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "New Circle"
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Constants.Colors.primary

        let row = UIStackView(arrangedSubviews: [tile, label])
        row.spacing = 14
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 52),
            tile.heightAnchor.constraint(equalToConstant: 52),
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 2),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -2),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
