import UIKit
import MapKit

/// Lightweight first-session flow: search a place, tap Add, it's saved into
/// the user's default circle. Three taps for three places. Reached from the
/// Start-your-map card and the no-circles empty state.
///
/// Redesigned 2026-10-09 (Wes: it looked bland, and there was no way to
/// close it — the only button sat under the keyboard): a close button in the
/// bar, a Done button that rides above the keyboard, three slots that fill
/// as places land, suggestion chips before the first search, and result
/// rows with the category icon and an Add pill.
class QuickStartAddPlacesViewController: BaseViewController {

    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    static let goal = 3
    private static let suggestions = ["Coffee", "Pizza", "Brunch", "Tacos", "Sushi", "Cocktails", "Bakery"]

    // MARK: - Properties
    private let targetCircle: Circle
    private var results: [MKMapItem] = []
    private var addedResultKeys: Set<String> = []
    private var savingResultKeys: Set<String> = []
    private var added: [(name: String, category: PlaceCategory)] = []
    private var searchTimer: Timer?
    private var lastQuery = ""

    // MARK: - UI Elements
    private let badgeView = GradientBadgeView(symbolName: "mappin.and.ellipse")

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Add \(QuickStartAddPlacesViewController.goal) places you love"
        label.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "They become your map — the one friends explore."
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    private let slotViews: [QuickStartSlotView] = (1...QuickStartAddPlacesViewController.goal).map { QuickStartSlotView(number: $0) }

    private let searchContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 14
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let searchIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let view = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: config))
        view.tintColor = Constants.Colors.secondaryLabel
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let searchField: UITextField = {
        let field = UITextField()
        field.placeholder = "Search a restaurant, café, shop…"
        field.font = UIFont.systemFont(ofSize: 16)
        field.textColor = Constants.Colors.label
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    /// "Try:" chips, shown until the first search
    private let chipsScrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()
    private let chipsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// "Searching…" / "No places found" under the field
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        label.isHidden = true
        return label
    }()

    private let resultsTableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 68, bottom: 0, right: 16)
        tableView.rowHeight = 68
        tableView.keyboardDismissMode = .onDrag
        tableView.register(QuickStartResultCell.self, forCellReuseIdentifier: QuickStartResultCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private lazy var doneButton = UIButton.primaryButton(title: "Skip for now")

    // MARK: - Init
    init(targetCircle: Circle) {
        self.targetCircle = targetCircle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationItem.title = ""
        // A way out, always visible (the Done button used to be the only one,
        // and the keyboard covered it)
        addNavigationBarButton(image: "xmark.circle.fill", position: .right, action: #selector(closeTapped))
        navigationController?.navigationBar.tintColor = Constants.Colors.secondaryLabel
        setupUI()
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        resultsTableView.delegate = self
        resultsTableView.dataSource = self
        updateDoneButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchField.becomeFirstResponder()
    }

    // MARK: - Setup
    private func setupUI() {
        // Hero: badge beside the title
        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titles.axis = .vertical
        titles.spacing = 3
        let hero = UIStackView(arrangedSubviews: [badgeView, titles])
        hero.axis = .horizontal
        hero.alignment = .center
        hero.spacing = 14
        badgeView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        badgeView.heightAnchor.constraint(equalToConstant: 56).isActive = true

        // Three slots that fill as places are added
        let slots = UIStackView(arrangedSubviews: slotViews)
        slots.axis = .horizontal
        slots.distribution = .fillEqually
        slots.spacing = 8
        slots.heightAnchor.constraint(equalToConstant: 52).isActive = true

        // Search field in a rounded container
        searchContainer.addSubview(searchIcon)
        searchContainer.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchContainer.heightAnchor.constraint(equalToConstant: 48),
            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 14),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor)
        ])

        // Suggestion chips
        let tryLabel = UILabel()
        tryLabel.text = "Try"
        tryLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        tryLabel.textColor = Constants.Colors.secondaryLabel
        chipsStack.addArrangedSubview(tryLabel)
        for suggestion in Self.suggestions {
            let chip = UIButton.pillButton(title: suggestion)
            chip.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            chip.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
            chip.layer.cornerRadius = 15
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chipsStack.addArrangedSubview(chip)
        }
        chipsScrollView.addSubview(chipsStack)
        NSLayoutConstraint.activate([
            chipsScrollView.heightAnchor.constraint(equalToConstant: 32),
            chipsStack.topAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.topAnchor),
            chipsStack.bottomAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.bottomAnchor),
            chipsStack.leadingAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.leadingAnchor),
            chipsStack.trailingAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.trailingAnchor),
            chipsStack.heightAnchor.constraint(equalTo: chipsScrollView.frameLayoutGuide.heightAnchor)
        ])

        let header = UIStackView(arrangedSubviews: [hero, slots, searchContainer, chipsScrollView, statusLabel])
        header.axis = .vertical
        header.spacing = 14
        header.setCustomSpacing(10, after: searchContainer)
        header.setCustomSpacing(6, after: chipsScrollView)
        header.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(resultsTableView)
        view.addSubview(doneButton)
        doneButton.layer.cornerRadius = 14
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            resultsTableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            resultsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsTableView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -10),

            doneButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            // Above the keyboard while it's up, at the safe area when it's not
            doneButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])
    }

    // MARK: - Search
    @objc private func searchTextChanged() {
        let text = searchField.text ?? ""
        chipsScrollView.isHidden = !text.trimmingCharacters(in: .whitespaces).isEmpty
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.performSearch(query: text)
        }
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard let text = sender.title(for: .normal) else { return }
        searchField.text = text
        searchTextChanged()
        searchTimer?.fire()
    }

    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        lastQuery = trimmed
        guard trimmed.count >= 2 else {
            results = []
            resultsTableView.reloadData()
            setStatus(nil)
            return
        }
        setStatus("Searching…")

        // Near the person when the app knows where they are (no new request)
        var region: MKCoordinateRegion?
        if let here = LocationService.shared.cachedLocation?.coordinate {
            region = MKCoordinateRegion(center: here, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        }
        AppleMapsService.shared.searchPlaces(query: trimmed, region: region) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.lastQuery == trimmed else { return }   // a newer search won
                switch result {
                case .success(let items):
                    self.results = items
                    self.setStatus(items.isEmpty ? "No places found for “\(trimmed)” — try the full name" : nil)
                case .failure:
                    self.results = []
                    self.setStatus("Couldn't search right now. Check your connection and try again.")
                }
                self.resultsTableView.reloadData()
            }
        }
    }

    private func setStatus(_ text: String?) {
        statusLabel.text = text
        statusLabel.isHidden = text == nil
    }

    private func resultKey(for item: MKMapItem) -> String {
        let coordinate = item.placemark.coordinate
        return "\(item.name ?? "")|\(coordinate.latitude)|\(coordinate.longitude)"
    }

    // MARK: - Adding
    private func addPlace(from item: MKMapItem) {
        let key = resultKey(for: item)
        guard !addedResultKeys.contains(key), !savingResultKeys.contains(key) else { return }
        savingResultKeys.insert(key)
        resultsTableView.reloadData()

        let details = AppleMapsService.shared.fetchPlaceDetails(mapItem: item)

        PlaceService.shared.createPlace(
            name: details.name,
            description: nil,
            address: details.address,
            category: details.category,
            circleId: targetCircle.id,
            website: details.website,
            phone: details.phoneNumber,
            location: details.coordinate
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.savingResultKeys.remove(key)

                switch result {
                case .success:
                    self.addedResultKeys.insert(key)
                    self.added.append((details.name, details.category))
                    self.placeLanded()
                    // Let the home screen refresh its map/data
                    NotificationCenter.default.post(name: Notification.Name("PlaceAdded"), object: nil)
                case .failure(let error):
                    self.showError(error)
                }
                self.resultsTableView.reloadData()
            }
        }
    }

    /// Fills the next slot, updates the button, celebrates the goal.
    private func placeLanded() {
        let index = added.count - 1
        if index < slotViews.count {
            slotViews[index].fill(name: added[index].name, category: added[index].category)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        updateDoneButton()
        if added.count == Self.goal {
            UIView.transition(with: titleLabel, duration: 0.3, options: .transitionCrossDissolve) {
                self.titleLabel.text = "Your map has started 🎉"
                self.subtitleLabel.text = "Add a few more, or tap Done."
            }
        }
    }

    private func updateDoneButton() {
        let count = added.count
        let outlined = count == 0
        doneButton.setTitle(
            count == 0 ? "Skip for now"
                : count < Self.goal ? "Done · \(count) of \(Self.goal) added"
                : "Done 🎉",
            for: .normal)
        doneButton.backgroundColor = outlined ? .clear : Constants.Colors.primary
        doneButton.setTitleColor(outlined ? Constants.Colors.secondaryLabel : .white, for: .normal)
        doneButton.layer.borderWidth = outlined ? 1 : 0
        doneButton.layer.borderColor = Constants.Colors.separator.cgColor
    }

    @objc private func doneTapped() { dismiss(animated: true) }
    @objc private func closeTapped() { dismiss(animated: true) }
}

// MARK: - UITextFieldDelegate
extension QuickStartAddPlacesViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        searchTimer?.invalidate()
        performSearch(query: textField.text ?? "")
        return true
    }
}

// MARK: - UITableViewDataSource & Delegate
extension QuickStartAddPlacesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: QuickStartResultCell.reuseId, for: indexPath) as! QuickStartResultCell
        guard indexPath.row < results.count else { return cell }
        let item = results[indexPath.row]
        let key = resultKey(for: item)
        let state: QuickStartResultCell.State = addedResultKeys.contains(key) ? .added
            : savingResultKeys.contains(key) ? .saving : .available
        let category = AppleMapItemFormFill.categoryMapping(poiCategory: item.pointOfInterestCategory, name: item.name).category
        cell.configure(name: item.name ?? "Unnamed place", address: item.placemark.title, category: category, state: state)
        cell.onAdd = { [weak self] in self?.addPlace(from: item) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < results.count else { return }
        addPlace(from: results[indexPath.row])
    }
}

// MARK: - Result row

/// Category icon, name, address, and an Add pill that becomes a spinner,
/// then "Added".
final class QuickStartResultCell: UITableViewCell {
    static let reuseId = "QuickStartResultCell"
    enum State { case available, saving, added }

    var onAdd: (() -> Void)?

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        return label
    }()
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = Constants.Colors.secondaryLabel
        return label
    }()
    private lazy var addButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Add", style: .primary)
        button.layer.cornerRadius = 15
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        button.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        return button
    }()
    private let spinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        return spinner
    }()
    private let addedLabel: UILabel = {
        let label = UILabel()
        label.text = "Added ✓"
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.success
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        let text = UIStackView(arrangedSubviews: [nameLabel, addressLabel])
        text.axis = .vertical
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false

        for v in [iconView, text, addButton, spinner, addedLabel] { contentView.addSubview(v) }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),

            text.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            text.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -10),

            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            addButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: addButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            addedLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            addedLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        addButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        addedLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, address: String?, category: PlaceCategory, state: State) {
        nameLabel.text = name
        addressLabel.text = address
        addressLabel.isHidden = (address ?? "").isEmpty
        iconView.image = UIImage(systemName: category.systemIconName)
        iconView.tintColor = category.color
        switch state {
        case .available:
            addButton.isHidden = false; addedLabel.isHidden = true; spinner.stopAnimating()
        case .saving:
            addButton.isHidden = true; addedLabel.isHidden = true; spinner.startAnimating()
        case .added:
            addButton.isHidden = true; addedLabel.isHidden = false; spinner.stopAnimating()
        }
        accessibilityLabel = state == .added ? "\(name), added" : name
    }

    @objc private func addTapped() { onAdd?() }
}

// MARK: - Progress slot

/// One of the three places: a numbered dashed slot until a place lands,
/// then its category icon and name on a tinted card.
final class QuickStartSlotView: UIView {
    private let number: Int
    private let numberLabel = UILabel()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let dashedBorder = CAShapeLayer()

    init(number: Int) {
        self.number = number
        super.init(frame: .zero)
        layer.cornerRadius = 12
        backgroundColor = Constants.Colors.secondaryBackground

        dashedBorder.fillColor = nil
        dashedBorder.strokeColor = Constants.Colors.separator.cgColor
        dashedBorder.lineDashPattern = [5, 4]
        dashedBorder.lineWidth = 1.5
        layer.addSublayer(dashedBorder)

        numberLabel.text = "\(number)"
        numberLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        numberLabel.textColor = Constants.Colors.tertiaryLabel
        numberLabel.textAlignment = .center

        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        iconView.isHidden = true
        nameLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = Constants.Colors.label
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isHidden = true

        let filled = UIStackView(arrangedSubviews: [iconView, nameLabel])
        filled.axis = .vertical
        filled.alignment = .center
        filled.spacing = 2
        for v in [numberLabel, filled] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            numberLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            filled.centerYAnchor.constraint(equalTo: centerYAnchor),
            filled.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            filled.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])
        isAccessibilityElement = true
        accessibilityLabel = "Place \(number), empty"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        dashedBorder.frame = bounds
        dashedBorder.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 12).cgPath
    }

    func fill(name: String, category: PlaceCategory) {
        iconView.image = UIImage(systemName: category.systemIconName)
        iconView.tintColor = category.color
        nameLabel.text = name
        accessibilityLabel = "Place \(number): \(name)"
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.4) {
            self.numberLabel.isHidden = true
            self.iconView.isHidden = false
            self.nameLabel.isHidden = false
            self.dashedBorder.isHidden = true
            self.backgroundColor = category.color.withAlphaComponent(0.14)
            self.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        } completion: { _ in
            UIView.animate(withDuration: 0.2) { self.transform = .identity }
        }
    }
}

// MARK: - Gradient badge

/// A round primary→accent gradient with a white symbol: the sheet's mark.
final class GradientBadgeView: UIView {
    private let gradient = CAGradientLayer()
    private let symbolView = UIImageView()

    init(symbolName: String) {
        super.init(frame: .zero)
        gradient.colors = [Constants.Colors.primary.cgColor, Constants.Colors.accent.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradient)
        layer.shadowColor = Constants.Colors.primary.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)

        symbolView.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold))
        symbolView.tintColor = .white
        symbolView.contentMode = .center
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = bounds.width / 2
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        gradient.colors = [Constants.Colors.primary.cgColor, Constants.Colors.accent.cgColor]
    }
}
