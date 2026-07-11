import UIKit
import MapKit

/// Super-user form for enrolling a venue in the sticker program from the phone.
/// Search for the place (MapKit), add the owner's contact + reward offers, and
/// on create the backend resolves the Google place ID, generates both QR codes,
/// and emails them to you for printing.
class CreateVenueViewController: BaseViewController {

    // MARK: - Properties

    var onVenueCreated: (() -> Void)?

    private var searchCompleter = MKLocalSearchCompleter()
    private var searchResults: [MKLocalSearchCompletion] = []

    private var selectedName: String?
    private var selectedAddress: String?
    private var selectedCoordinate: CLLocationCoordinate2D?
    private var selectedCategory = "restaurant"
    private var offers: [VenueOfferDraft] = []

    private let categories = ["restaurant", "cafe", "bar", "retail", "fitness", "service", "entertainment", "other"]

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

    private let searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.placeholder = "Search for the place"
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
        label.text = "No place selected yet"
        return label
    }()

    private lazy var categoryButton = UIButton.secondaryButton(title: "Category: restaurant")

    private let contactNameField: UITextField = {
        let field = UITextField()
        field.placeholder = "Owner / contact name (optional)"
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .words
        return field
    }()

    private let contactEmailField: UITextField = {
        let field = UITextField()
        field.placeholder = "Contact email — gets the monthly stats report"
        field.borderStyle = .roundedRect
        field.keyboardType = .emailAddress
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        return field
    }()

    private let offersHeaderLabel: UILabel = {
        let label = UILabel()
        label.text = "Reward offers (redeemed at the counter)"
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        return label
    }()

    private let offersStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }()

    private lazy var addOfferButton = UIButton.secondaryButton(title: "+ Add Offer")
    private lazy var createButton = UIButton.primaryButton(title: "Create Venue & Email Me the QR Codes")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Venue"
        view.backgroundColor = .systemBackground

        searchCompleter.delegate = self
        searchCompleter.resultTypes = .pointOfInterest
        searchBar.delegate = self
        resultsTableView.dataSource = self
        resultsTableView.delegate = self
        resultsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "ResultCell")

        categoryButton.addTarget(self, action: #selector(categoryTapped), for: .touchUpInside)
        addOfferButton.addTarget(self, action: #selector(addOfferTapped), for: .touchUpInside)
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)

        setupLayout()
        refreshOffersUI()
    }

    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let sectionLabel = UILabel()
        sectionLabel.text = "Place"
        sectionLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)

        [sectionLabel, searchBar, resultsTableView, selectedPlaceLabel, categoryButton,
         contactNameField, contactEmailField,
         offersHeaderLabel, offersStack, addOfferButton, createButton].forEach {
            contentStack.addArrangedSubview($0)
        }
        contentStack.setCustomSpacing(20, after: selectedPlaceLabel)
        contentStack.setCustomSpacing(24, after: categoryButton)
        contentStack.setCustomSpacing(24, after: addOfferButton)

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

            resultsTableView.heightAnchor.constraint(equalToConstant: 220),
            contactNameField.heightAnchor.constraint(equalToConstant: 44),
            contactEmailField.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    // MARK: - Offers

    private func refreshOffersUI() {
        offersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if offers.isEmpty {
            let label = UILabel()
            label.text = "No offers yet — add at least one (e.g. \"Free drip coffee\" for 250 pts)"
            label.font = UIFont.systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            offersStack.addArrangedSubview(label)
            return
        }

        for (index, offer) in offers.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8

            let label = UILabel()
            label.text = "🎁 \(offer.title) — \(offer.pointsCost) pts"
            label.font = UIFont.systemFont(ofSize: 14)
            label.numberOfLines = 0

            let removeButton = UIButton.iconButton(systemName: "trash")
            removeButton.tintColor = .systemRed
            removeButton.tag = index
            removeButton.addTarget(self, action: #selector(removeOfferTapped(_:)), for: .touchUpInside)

            row.addArrangedSubview(label)
            row.addArrangedSubview(removeButton)
            offersStack.addArrangedSubview(row)
        }
    }

    @objc private func addOfferTapped() {
        AlertPresenter.showTextInput(
            title: "New Offer",
            message: "What does the customer get?",
            placeholder: "e.g. Free drip coffee",
            from: self
        ) { [weak self] title in
            guard let self = self,
                  let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return }

            AlertPresenter.showTextInput(
                title: "Points Cost",
                message: "How many points to redeem \"\(title)\"? (25 pts ≈ one visit)",
                placeholder: "250",
                keyboardType: .numberPad,
                from: self
            ) { [weak self] points in
                guard let self = self,
                      let points = Int(points ?? ""), points > 0 else { return }
                self.offers.append(VenueOfferDraft(title: title, pointsCost: points))
                self.refreshOffersUI()
            }
        }
    }

    @objc private func removeOfferTapped(_ sender: UIButton) {
        guard sender.tag < offers.count else { return }
        offers.remove(at: sender.tag)
        refreshOffersUI()
    }

    // MARK: - Category

    @objc private func categoryTapped() {
        let actions = categories.map { category in
            (title: category.capitalized, style: UIAlertAction.Style.default, handler: { [weak self] in
                self?.selectedCategory = category
                self?.categoryButton.setTitle("Category: \(category)", for: .normal)
            })
        }
        AlertPresenter.showActionSheet(title: "Venue Category", actions: actions, from: self)
    }

    // MARK: - Create

    @objc private func createTapped() {
        guard let name = selectedName, let address = selectedAddress else {
            AlertPresenter.showError(message: "Search for and select the place first", from: self)
            return
        }
        guard !offers.isEmpty else {
            AlertPresenter.showError(message: "Add at least one reward offer", from: self)
            return
        }

        let draft = VenueDraft(
            venueName: name,
            placeAddress: address,
            category: selectedCategory,
            contactName: contactNameField.text,
            contactEmail: contactEmailField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: selectedCoordinate?.latitude,
            longitude: selectedCoordinate?.longitude,
            offers: offers
        )

        let loading = AlertPresenter.showLoading(message: "Creating venue...", from: self)
        createButton.isEnabled = false

        RewardsService.shared.createVenue(draft) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    self.createButton.isEnabled = true

                    switch result {
                    case .success(let venue):
                        let emailLine = venue.emailSent
                            ? "Both QR codes were emailed to \(venue.emailedTo ?? "you") — print them and you're set."
                            : "QR email couldn't be sent — use \"Email QR codes to me\" from the venue list to retry."
                        AlertPresenter.showSuccess(
                            title: "\(venue.venueName) is enrolled! 🎉",
                            message: "Window code: \(venue.windowCode)\nRegister code: \(venue.registerCode)\n\n\(emailLine)",
                            from: self
                        ) {
                            self.onVenueCreated?()
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

// MARK: - Search

extension CreateVenueViewController: UISearchBarDelegate, MKLocalSearchCompleterDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            searchResults = []
            resultsTableView.isHidden = true
            resultsTableView.reloadData()
        } else {
            searchCompleter.queryFragment = searchText
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        resultsTableView.isHidden = searchResults.isEmpty
        resultsTableView.reloadData()
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        searchResults = []
        resultsTableView.isHidden = true
    }
}

// MARK: - Results table

extension CreateVenueViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ResultCell", for: indexPath)
        let result = searchResults[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = result.title
        config.secondaryText = result.subtitle
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let completion = searchResults[indexPath.row]

        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        search.start { [weak self] response, _ in
            DispatchQueue.main.async {
                guard let self = self, let item = response?.mapItems.first else { return }

                self.selectedName = item.name ?? completion.title
                self.selectedCoordinate = item.placemark.coordinate

                let placemark = item.placemark
                let addressParts = [placemark.subThoroughfare, placemark.thoroughfare,
                                    placemark.locality, placemark.administrativeArea, placemark.postalCode]
                let joined = addressParts.compactMap { $0 }.joined(separator: " ")
                self.selectedAddress = joined.isEmpty ? completion.subtitle : joined

                self.selectedPlaceLabel.text = "📍 \(self.selectedName ?? "")\n\(self.selectedAddress ?? "")"
                self.selectedPlaceLabel.textColor = .label
                self.searchBar.resignFirstResponder()
                self.resultsTableView.isHidden = true
            }
        }
    }
}
