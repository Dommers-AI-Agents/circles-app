import UIKit
import MapKit

/// Manage Store → Store details (2026-10-23): the store's shared details,
/// the ones every saver's copy shows. Name, category, description, phone,
/// website, and the address (map-confirmed, since a typo moves the pin).
/// Before this the owner edited them by tapping fields on the place page;
/// now Manage Store is the one place for every edit, reached from the place
/// page's owner bar and the profile's store icon.
///
/// Saves go through PlaceDetailsService, the one shared-details path
/// (services/venueDetailsService on the server: the canonical record, copied
/// to every save).
final class VenueDetailsViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { place == nil }
    override var loadsDataOnViewDidLoad: Bool { true }

    /// Called after a save, with the store's new name
    var onSaved: ((Place) -> Void)?

    private let placeId: String
    private var place: Place?

    private enum Row: CaseIterable {
        case name, category, description, phone, website, address
    }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 60
        return table
    }()

    init(placeId: String) {
        self.placeId = placeId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Store details"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func loadData(completion: (() -> Void)? = nil) {
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { completion?(); return }
                switch result {
                case .success(let place):
                    self.place = place
                    self.tableView.reloadData()
                case .failure(let error):
                    if self.place == nil { self.showError(error) }
                }
                completion?()
            }
        }
    }

    // MARK: - Editors

    private func edit(_ row: Row) {
        guard let place else { return }
        switch row {
        case .name:
            prompt(title: "Store name", initialText: place.name, confirmTitle: "Save") { [weak self] value in
                let name = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name != place.name else { return }
                self?.save(["name": name])
            }
        case .category:
            let categories: [PlaceCategory] = [.restaurant, .cafe, .bar, .hotel, .retail, .service, .attraction, .other]
            AlertPresenter.showActionSheet(
                title: "Category",
                actions: categories.map { category in
                    (title: category.displayName, style: .default, handler: { [weak self] in
                        self?.save(["category": category.rawValue])
                    })
                },
                from: self
            )
        case .description:
            // A half-sheet with the text view pinned to the keyboard
            let editor = OwnerDescriptionEditorViewController()
            editor.initialText = StoreDescriptionText.strippingContactLines(place.description)
            editor.onSave = { [weak self] text in
                self?.save(["description": StoreDescriptionText.strippingContactLines(text)])
            }
            let nav = UINavigationController(rootViewController: editor)
            if let sheet = nav.sheetPresentationController { sheet.detents = [.medium(), .large()] }
            present(nav, animated: true)
        case .phone:
            prompt(title: "Phone", initialText: place.phone, keyboardType: .phonePad, confirmTitle: "Save") { [weak self] value in
                self?.save(["phone": (value ?? "").trimmingCharacters(in: .whitespaces)])
            }
        case .website:
            prompt(title: "Website", placeholder: "https://", initialText: place.website, keyboardType: .URL, confirmTitle: "Save") { [weak self] value in
                self?.save(["website": (value ?? "").trimmingCharacters(in: .whitespaces)])
            }
        case .address:
            // Map-confirmed: the owner picks the spot, not just the words
            let search = PlaceAddressSearchViewController(placeName: place.name, currentLocation: place.location?.clLocation)
            search.delegate = self
            present(UINavigationController(rootViewController: search), animated: true)
        }
    }

    private func prompt(title: String, placeholder: String? = nil, initialText: String?,
                               keyboardType: UIKeyboardType = .default, confirmTitle: String,
                               onSubmit: @escaping (String?) -> Void) {
        AlertPresenter.showTextInput(title: title, placeholder: placeholder, initialText: initialText,
                                     keyboardType: keyboardType, confirmTitle: confirmTitle, from: self, onSubmit: onSubmit)
    }

    // MARK: - Save

    private func save(_ fields: [String: Any]) {
        guard let place else { return }
        let loading = AlertPresenter.showLoading(message: "Saving\u{2026}", from: self)
        PlaceDetailsService.shared.update(placeId: place.globalPlaceId ?? place.id, fields: fields) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.didSave()
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func saveAddress(_ address: String, coordinate: CLLocationCoordinate2D) {
        guard let place else { return }
        let loading = AlertPresenter.showLoading(message: "Saving the new address\u{2026}", from: self)
        PlaceService.shared.updatePlaceAddress(id: place.id, address: address, coordinate: coordinate) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success: self.didSave()
                    case .failure(let error): self.showError(error)
                    }
                }
            }
        }
    }

    /// The place as everyone now sees it; the place page re-reads it too
    private func didSave() {
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let updated) = result {
                    self.place = updated
                    self.tableView.reloadData()
                    self.onSaved?(updated)
                }
                NotificationCenter.default.post(name: .storeDetailsChanged, object: nil,
                                                userInfo: ["globalPlaceId": self.place?.globalPlaceId ?? self.placeId])
                self.showSuccess("Updated on your place page")
            }
        }
    }
}

extension VenueDetailsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { place == nil ? 0 : 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { Row.allCases.count }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Everyone who saved your store sees these. Hours, photos and your menu are in Manage Store too."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryType = .disclosureIndicator
        var config = UIListContentConfiguration.subtitleCell()
        config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
        config.secondaryTextProperties.numberOfLines = 3
        let row = Row.allCases[indexPath.row]
        let empty = { (text: String?) -> Bool in (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch row {
        case .name:
            config.text = "Name"
            config.secondaryText = place?.name
            config.image = UIImage(systemName: "textformat")
        case .category:
            config.text = "Category"
            config.secondaryText = place?.displayCategory
            config.image = UIImage(systemName: "tag")
        case .description:
            let text = StoreDescriptionText.strippingContactLines(place?.description)
            config.text = "Description"
            config.secondaryText = text.isEmpty ? "Add a few words about your store" : text
            config.image = UIImage(systemName: "text.alignleft")
        case .phone:
            config.text = "Phone"
            config.secondaryText = empty(place?.phone) ? "Add a phone number" : place?.phone
            config.image = UIImage(systemName: "phone")
        case .website:
            config.text = "Website"
            config.secondaryText = empty(place?.website) ? "Add your website" : place?.website
            config.image = UIImage(systemName: "globe")
        case .address:
            config.text = "Address"
            config.secondaryText = place?.address
            config.image = UIImage(systemName: "mappin.and.ellipse")
        }
        config.imageProperties.tintColor = Constants.Colors.primary
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        edit(Row.allCases[indexPath.row])
    }
}

extension VenueDetailsViewController: PlaceAddressSearchViewControllerDelegate {
    func placeAddressSearchViewController(_ controller: PlaceAddressSearchViewController, didSelectMapItem mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        let address = [placemark.subThoroughfare, placemark.thoroughfare, placemark.locality,
                       placemark.administrativeArea, placemark.postalCode]
            .compactMap { $0 }.joined(separator: ", ")
        saveAddress(address, coordinate: placemark.coordinate)
    }

    func placeAddressSearchViewControllerDidCancel(_ controller: PlaceAddressSearchViewController) {}
}
