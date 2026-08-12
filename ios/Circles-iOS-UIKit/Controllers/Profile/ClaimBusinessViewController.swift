import UIKit
import MapKit

/// Store-owner flow for claiming a business that no user has saved yet.
/// Step 1: search Apple Maps (MKLocalSearch) for the business.
/// Step 2: confirm the pick and submit contact info — the claim is emailed to
/// the admin, who verifies ownership and approves (same flow as claiming from
/// a place page).
class ClaimBusinessViewController: BaseViewController {

    // MARK: - Properties

    private var searchResults: [MKMapItem] = []
    private var selectedMapItem: MKMapItem?
    private var pendingSearch: DispatchWorkItem?
    private var activeSearch: MKLocalSearch?

    override var loadsDataOnViewDidLoad: Bool { false }

    // MARK: - UI Elements

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        return scrollView
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 30, right: 20)
        return stack
    }()

    private let introLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.text = "Search for your business, then tell us how to reach you. We'll verify that you own it and set you up as its owner."
        return label
    }()

    private let searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.placeholder = "Search for your business"
        bar.searchBarStyle = .minimal
        return bar
    }()

    private let resultsTableView: UITableView = {
        let table = UITableView()
        table.isHidden = true
        table.layer.cornerRadius = 10
        table.layer.borderWidth = 0.5
        table.layer.borderColor = UIColor.separator.cgColor
        return table
    }()

    private let selectedPlaceLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.text = "No business selected yet"
        return label
    }()

    private let contactHeaderLabel: UILabel = {
        let label = UILabel()
        label.text = "Your contact info"
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        return label
    }()

    private let contactNameField: UITextField = {
        let field = UITextField()
        field.placeholder = "Your name"
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .words
        return field
    }()

    private let contactEmailField: UITextField = {
        let field = UITextField()
        field.placeholder = "Business email"
        field.borderStyle = .roundedRect
        field.keyboardType = .emailAddress
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        return field
    }()

    private let contactPhoneField: UITextField = {
        let field = UITextField()
        field.placeholder = "Phone (optional)"
        field.borderStyle = .roundedRect
        field.keyboardType = .phonePad
        return field
    }()

    private let messageField: UITextField = {
        let field = UITextField()
        field.placeholder = "Message (optional, e.g. \"I'm the owner\")"
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .sentences
        return field
    }()

    private lazy var submitButton = UIButton.primaryButton(title: "Submit claim")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Claim Your Business"
        view.backgroundColor = .systemBackground

        searchBar.delegate = self
        resultsTableView.dataSource = self
        resultsTableView.delegate = self
        resultsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "BusinessResultCell")

        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        setupLayout()
        prefillContactInfo()
        setContactFormVisible(false)

        // Warm up the location so searches are biased to where the owner is
        LocationService.shared.getCurrentLocation { _ in }
    }

    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        [introLabel, searchBar, resultsTableView, selectedPlaceLabel,
         contactHeaderLabel, contactNameField, contactEmailField,
         contactPhoneField, messageField, submitButton].forEach {
            contentStack.addArrangedSubview($0)
        }
        contentStack.setCustomSpacing(20, after: selectedPlaceLabel)
        contentStack.setCustomSpacing(24, after: messageField)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            resultsTableView.heightAnchor.constraint(equalToConstant: 260),
            contactNameField.heightAnchor.constraint(equalToConstant: 44),
            contactEmailField.heightAnchor.constraint(equalToConstant: 44),
            contactPhoneField.heightAnchor.constraint(equalToConstant: 44),
            messageField.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func prefillContactInfo() {
        guard let user = AuthService.shared.currentUser else { return }
        contactNameField.text = user.displayName
        contactEmailField.text = user.email
    }

    private func setContactFormVisible(_ visible: Bool) {
        [contactHeaderLabel, contactNameField, contactEmailField,
         contactPhoneField, messageField, submitButton].forEach {
            $0.isHidden = !visible
        }
    }

    // MARK: - Search

    private func performSearch(for query: String) {
        activeSearch?.cancel()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let location = LocationService.shared.lastKnownLocation {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }

        let search = MKLocalSearch(request: request)
        activeSearch = search
        search.start { [weak self] response, _ in
            DispatchQueue.main.async {
                guard let self = self, self.activeSearch === search else { return }
                self.searchResults = response?.mapItems ?? []
                self.resultsTableView.isHidden = self.searchResults.isEmpty
                self.resultsTableView.reloadData()
            }
        }
    }

    fileprivate func formattedAddress(_ placemark: MKPlacemark) -> String {
        let street: String? = placemark.thoroughfare.map { thoroughfare in
            placemark.subThoroughfare.map { "\($0) \(thoroughfare)" } ?? thoroughfare
        }
        let parts = [street, placemark.locality, placemark.administrativeArea, placemark.postalCode]
            .compactMap { $0 }
        return parts.joined(separator: ", ")
    }

    fileprivate func select(_ item: MKMapItem) {
        selectedMapItem = item
        let name = item.name ?? "Unknown"
        let address = formattedAddress(item.placemark)
        selectedPlaceLabel.text = "📍 \(name)\n\(address)"
        selectedPlaceLabel.textColor = .label

        searchBar.resignFirstResponder()
        resultsTableView.isHidden = true
        setContactFormVisible(true)
    }

    // MARK: - Submit

    @objc private func submitTapped() {
        guard let item = selectedMapItem else {
            AlertPresenter.showError(message: "Search for and select your business first", from: self)
            return
        }

        let name = contactNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = contactEmailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, email.contains("@") else {
            AlertPresenter.showError(message: "Please provide your name and a valid business email so we can verify your claim.", from: self)
            return
        }

        let businessName = item.name ?? searchBar.text ?? ""
        let address = formattedAddress(item.placemark)
        let coordinate = item.placemark.coordinate

        let loading = AlertPresenter.showLoading(message: "Submitting...", from: self)
        submitButton.isEnabled = false

        RewardsService.shared.claimBusiness(
            name: businessName,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            phone: item.phoneNumber,
            website: item.url?.absoluteString,
            applePoiCategory: item.pointOfInterestCategory?.rawValue,
            contactName: name,
            contactEmail: email,
            contactPhone: contactPhoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            message: messageField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    self.submitButton.isEnabled = true

                    switch result {
                    case .success:
                        AlertPresenter.showSuccess(
                            message: "Claim submitted — we'll verify your ownership and be in touch.",
                            from: self
                        ) {
                            self.navigationController?.popViewController(animated: true)
                        }
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
}

// MARK: - UISearchBarDelegate

extension ClaimBusinessViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        pendingSearch?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            activeSearch?.cancel()
            searchResults = []
            resultsTableView.isHidden = true
            resultsTableView.reloadData()
            return
        }

        // Debounce — MKLocalSearch throttles aggressive callers
        let work = DispatchWorkItem { [weak self] in
            self?.performSearch(for: query)
        }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - Results table

extension ClaimBusinessViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BusinessResultCell", for: indexPath)
        let item = searchResults[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = item.name
        config.secondaryText = formattedAddress(item.placemark)
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        select(searchResults[indexPath.row])
    }
}
