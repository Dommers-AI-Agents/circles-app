import UIKit
import MapKit
import CoreLocation
import PhotosUI

protocol EditPlaceDelegate: AnyObject {
    func didUpdatePlace(_ updatedPlace: Place)
    func didDeletePlace(_ placeId: String)
}

class EditPlaceViewController: BaseViewController {
    
    // MARK: - Constants
    private enum Constants {
        enum Spacing {
            static let small: CGFloat = 8
            static let medium: CGFloat = 16
            static let large: CGFloat = 20
            static let xlarge: CGFloat = 32
        }
        
        enum FontSize {
            static let small: CGFloat = 14
            static let medium: CGFloat = 16
            static let large: CGFloat = 18
            static let xlarge: CGFloat = 20
            static let xxlarge: CGFloat = 24
        }
        
        enum Colors {
            static let primary = UIColor.systemBlue
            static let background = UIColor.systemBackground
            static let secondaryBackground = UIColor.secondarySystemBackground
            static let darkGray = UIColor.darkGray
            static let lightGray = UIColor.lightGray
            static let white = UIColor.white
        }
    }
    
    // MARK: - Properties
    private var place: Place
    private let locationManager = CLLocationManager()
    private var selectedLocation: CLLocationCoordinate2D?
    // Only fill the address from GPS after the user explicitly asks — the
    // authorization callback fires on delegate assignment, and an
    // unconditional startUpdatingLocation there overwrote the store's real
    // address with wherever the editor happened to be standing
    private var wantsCurrentLocation = false
    // Venue owner editing their store (not organizing a save): privacy/circle
    // controls hidden; the listing stays public
    weak var delegate: EditPlaceDelegate?

    // Shared details (name, address, category, description, phone, website,
    // hours) belong to the place record: editable only by the store's team
    // and admins (the server's detailRights), saved through
    // PlaceDetailsService. Locked until the rights arrive.
    private var canEditDetails = false
    private var globalPlaceId: String?
    private var libraryURLs: [String] = []
    private var selectedCategory: PlaceCategory = .other
    /// The address boxes as first filled. The split-into-boxes form can't
    /// round-trip every stored address ("1616, Camden Rd, …" lands one box
    /// off), so an address is only a change when someone edits the boxes.
    private var initialAddressText = ""
    /// Home/Work are private, device-local pins — always the owner's to edit.
    private var isHomeOrWork: Bool { place.id == "home-place" || place.id == "work-place" }
    /// Personal fields only exist on your own save. An admin or store owner
    /// may open Edit Place from someone else's save to fix shared details.
    private var isOwnSave: Bool { isHomeOrWork || place.isAddedByCurrentUser }

    private let formStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    private let photoStrip = PlacePhotoStripView()
    private lazy var lockedNote: UIButton = {
        let button = UIButton.captionLinkButton()
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.numberOfLines = 0
        button.setTitle("Details come from Google and Apple. Only the store's owner or an admin can change them. Report a problem ›", for: .normal)
        button.addTarget(self, action: #selector(flagPlaceInfoTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()
    private let categoryButton = UIButton.menuFieldButton()
    private lazy var hoursButton: UIButton = {
        let button = UIButton.menuFieldButton()
        button.addTarget(self, action: #selector(hoursTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()
    private let personalHeader: UILabel = {
        let label = UILabel()
        label.text = "Your save"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .bold)
        return label
    }()
    
    // MARK: - Configuration
    override var loadsDataOnViewDidLoad: Bool { false }
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.text = "Place Name"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let nameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter place name"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.text = "Category"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let customCategoryLabel: UILabel = {
        let label = UILabel()
        label.text = "Custom Category Name (subcategory of Other)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private let customCategoryTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "e.g., Coffee work, Study spot, etc."
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isHidden = true
        return textField
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Description (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.cornerRadius = 5
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.text = "Address"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let refreshAddressButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Refresh from Apple Maps", for: .normal)
        button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = false
        return button
    }()
    
    private let streetTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Street"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let cityTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "City"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let stateTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "State"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let zipCodeTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Zip Code"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .numberPad
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let countryTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Country"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let mapLabel: UILabel = {
        let label = UILabel()
        label.text = "Location"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.layer.cornerRadius = 12
        mapView.clipsToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        return mapView
    }()
    
    private let useCurrentLocationButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Use Current Location", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let privacyLabel: UILabel = {
        let label = UILabel()
        label.text = "Privacy"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Was a four-segment control whose titles were hardcoded as
    // ["Follow Circle", "Public", "Friends", "Private"] — with "Friends" being
    // the same tier Edit Circle called "My Network" and moments called
    // "Connections" — and whose values lived in a parallel array repeated three
    // times in this file. Titles and values now both come from PrivacyTier.
    private lazy var privacyPicker: PrivacyPickerButton = {
        let picker = PrivacyPickerButton(entity: .place, selected: .inheritCircle)
        picker.onEditInnerCircle = { [weak self] in
            self?.navigationController?.pushViewController(InnerCircleListsViewController(), animated: true)
        }
        return picker
    }()
    
    private let notesLabel: UILabel = {
        let label = UILabel()
        label.text = "Private note (only you can see this)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notesTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.cornerRadius = 5
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let tagsLabel: UILabel = {
        let label = UILabel()
        label.text = "Tags (optional, comma separated)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tagsTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "e.g. family-friendly, romantic, cheap"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let websiteLabel: UILabel = {
        let label = UILabel()
        label.text = "Website (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let websiteTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "https://example.com"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .URL
        textField.autocapitalizationType = .none
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let phoneLabel: UILabel = {
        let label = UILabel()
        label.text = "Phone (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let phoneTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "+1 (555) 123-4567"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .phonePad
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    // Photo UI elements
    
    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Save Changes", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let deleteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Unsave Place", for: .normal)
        button.setTitleColor(.red, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let moveToCircleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Move to Different Circle", for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Lifecycle
    
    init(place: Place) {
        self.place = place
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupLocationManager()
        setupActions()
        populateFields()
        applyDetailRights()
        loadRightsAndPhotos()
    }

    /// The controls for the place's shared details.
    private var detailControls: [UIView] {
        [nameTextField, categoryButton, descriptionTextView,
         streetTextField, cityTextField, stateTextField, zipCodeTextField, countryTextField,
         websiteTextField, phoneTextField, refreshAddressButton, useCurrentLocationButton, mapView]
    }

    /// Shared details: editable for the store's team and admins (and on a
    /// Home/Work pin), read-only with a Report link for everyone else.
    /// Personal fields show only on your own save.
    private func applyDetailRights() {
        let editable = canEditDetails || isHomeOrWork
        detailControls.forEach {
            $0.isUserInteractionEnabled = editable
            $0.alpha = editable ? 1 : 0.55
        }
        lockedNote.isHidden = editable
        hoursButton.isHidden = !canEditDetails || globalPlaceId == nil
        photoStrip.isHidden = isHomeOrWork
        [personalHeader, privacyLabel, privacyPicker, notesLabel, notesTextView, tagsLabel, tagsTextField,
         moveToCircleButton, deleteButton].forEach { $0.isHidden = !isOwnSave }
        if isHomeOrWork { [personalHeader, privacyLabel, privacyPicker].forEach { $0.isHidden = true } }
        // Which circle holds a save is a personal organizing choice — it's on
        // the place page's menu for that. Edit Place for an owner or admin is
        // about the place itself.
        moveToCircleButton.isHidden = !isOwnSave || canEditDetails
        updateCategoryUI()
        title = isOwnSave ? "Edit Place" : "Edit Place Details"
    }

    /// Who may change the shared details, and the photo library, from the
    /// place record (GET /places/global/:id).
    private func loadRightsAndPhotos() {
        guard !isHomeOrWork else { return }
        GlobalPlaceService.shared.getGlobalPlace(id: place.globalPlaceId ?? place.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let response) = result else { return }
                self.globalPlaceId = response.globalPlace.id
                self.canEditDetails = response.detailRights?.canEdit ?? false
                self.libraryURLs = response.globalPlace.photos?.map(\.url) ?? []
                self.photoStrip.configure(urls: self.libraryURLs, canManage: response.photoRights?.canManage ?? false)
                self.updateHoursTitle(response.globalPlace.googleData?.openingHours)
                self.applyDetailRights()
            }
        }
    }

    private func updateHoursTitle(_ hours: [OpeningHour]?) {
        var config = hoursButton.configuration
        config?.title = hours.map { OpeningHoursFormatter.todaySummary($0) }.flatMap { $0.isEmpty ? nil : "Hours · \($0)" } ?? "Set opening hours"
        config?.image = UIImage(systemName: "clock")
        config?.imagePadding = 8
        hoursButton.configuration = config
    }

    @objc private func hoursTapped() {
        guard let globalPlaceId else { return }
        let hours = VenueHoursViewController(placeId: globalPlaceId)
        hours.onSaved = { [weak self] saved in self?.updateHoursTitle(saved) }
        navigationController?.pushViewController(hours, animated: true)
    }

    // MARK: - Photos (the place's one library)

    private func openPhotoLibrary() {
        let gallery = PlaceGalleryViewController(placeId: globalPlaceId ?? place.globalPlaceId ?? place.id,
                                                 placeName: place.name, arranging: true)
        gallery.onAddPhoto = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
            self?.presentPhotoPicker()
        }
        gallery.onChanged = { [weak self] _ in self?.loadRightsAndPhotos() }
        navigationController?.pushViewController(gallery, animated: true)
    }

    private func presentPhotoPicker() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = PlacePhotoBatchSummary.selectionLimit
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func uploadToLibrary(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        let loading = showLoading(message: PlacePhotoBatchSummary.progress(current: 1, total: images.count))
        PlacePhotoBatchUploader.upload(images, to: place, progress: { current, total in
            loading.message = PlacePhotoBatchSummary.progress(current: current, total: total)
        }) { [weak self] added, failed in
            loading.dismiss(animated: true) {
                guard let self else { return }
                self.loadRightsAndPhotos()
                guard let summary = PlacePhotoBatchSummary.result(added: added.count, failed: failed) else { return }
                if failed == 0 { self.showSuccess(summary.message) }
                else { AlertPresenter.showError(title: summary.title, message: summary.message, from: self) }
            }
        }
    }

    @objc private func flagPlaceInfoTapped() {
        promptFlagPlaceInfo(placeId: place.id, placeName: place.name)
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Edit Place"

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveButtonTapped))

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(formStack)

        photoStrip.onAdd = { [weak self] in self?.presentPhotoPicker() }
        photoStrip.onOpenLibrary = { [weak self] in self?.openPhotoLibrary() }
        photoStrip.onPhotoTapped = { [weak self] index in
            guard let self, !self.libraryURLs.isEmpty else { return }
            self.present(StorefrontPhotoViewerViewController(urls: self.libraryURLs, startingAt: index), animated: true)
        }

        func row(_ views: [UIView], spacing: CGFloat = Constants.Spacing.medium) -> UIStackView {
            let stack = UIStackView(arrangedSubviews: views)
            stack.axis = .horizontal
            stack.spacing = spacing
            stack.distribution = .fillEqually
            return stack
        }
        let addressHeader = UIStackView(arrangedSubviews: [addressLabel, UIView(), refreshAddressButton])
        addressHeader.axis = .horizontal
        let locationButtonRow = UIStackView(arrangedSubviews: [UIView(), useCurrentLocationButton])
        locationButtonRow.axis = .horizontal
        let cityRow = row([cityTextField, stateTextField])
        let zipRow = row([zipCodeTextField, countryTextField])

        // One column, top to bottom: the place's photos and shared details,
        // then (on your own save) your personal fields. Hidden rows collapse.
        let ordered: [UIView] = [
            photoStrip, lockedNote,
            nameLabel, nameTextField,
            categoryLabel, categoryButton, customCategoryLabel, customCategoryTextField,
            descriptionLabel, descriptionTextView,
            addressHeader, streetTextField, cityRow, zipRow,
            mapLabel, mapView, locationButtonRow,
            websiteLabel, websiteTextField, phoneLabel, phoneTextField, hoursButton,
            personalHeader, privacyLabel, privacyPicker, notesLabel, notesTextView, tagsLabel, tagsTextField,
            moveToCircleButton, deleteButton
        ]
        ordered.forEach { formStack.addArrangedSubview($0) }
        // A little more air before each section label than after it
        [lockedNote, nameTextField, categoryButton, customCategoryTextField, descriptionTextView,
         zipRow, locationButtonRow, websiteTextField, phoneTextField, hoursButton, privacyPicker,
         notesTextView, tagsTextField, moveToCircleButton]
            .forEach { formStack.setCustomSpacing(Constants.Spacing.large, after: $0) }
        formStack.setCustomSpacing(Constants.Spacing.xlarge, after: hoursButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            formStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.large),
            formStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            formStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            formStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.xlarge),

            nameTextField.heightAnchor.constraint(equalToConstant: 40),
            customCategoryTextField.heightAnchor.constraint(equalToConstant: 40),
            descriptionTextView.heightAnchor.constraint(equalToConstant: 80),
            streetTextField.heightAnchor.constraint(equalToConstant: 40),
            cityTextField.heightAnchor.constraint(equalToConstant: 40),
            zipCodeTextField.heightAnchor.constraint(equalToConstant: 40),
            mapView.heightAnchor.constraint(equalToConstant: 180),
            notesTextView.heightAnchor.constraint(equalToConstant: 80),
            tagsTextField.heightAnchor.constraint(equalToConstant: 40),
            websiteTextField.heightAnchor.constraint(equalToConstant: 40),
            phoneTextField.heightAnchor.constraint(equalToConstant: 40),
            categoryButton.heightAnchor.constraint(equalToConstant: 44),
            hoursButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    /// The full category list (the server's), as a menu.
    private func updateCategoryUI() {
        categoryButton.menu = UIMenu(children: PlaceCategory.allCases.map { category in
            UIAction(title: category.displayName, state: category == selectedCategory ? .on : .off) { [weak self] _ in
                self?.selectedCategory = category
                self?.updateCategoryUI()
            }
        })
        categoryButton.showsMenuAsPrimaryAction = true
        var config = categoryButton.configuration
        config?.title = selectedCategory.displayName
        categoryButton.configuration = config
        // The custom name is your own label for an "Other" place
        let showCustom = selectedCategory == .other && isOwnSave
        customCategoryLabel.isHidden = !showCustom
        customCategoryTextField.isHidden = !showCustom
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Show current place location on map
        if let location = place.location?.clLocation {
            selectedLocation = location.coordinate
            
            let region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            mapView.setRegion(region, animated: false)
            
            // Add annotation
            let annotation = MKPointAnnotation()
            annotation.coordinate = location.coordinate
            annotation.title = place.name
            mapView.addAnnotation(annotation)
        }
        
        // Add tap gesture recognizer to the map
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
    }
    
    private func setupActions() {
        // Add button actions
        useCurrentLocationButton.addTarget(self, action: #selector(useCurrentLocationButtonTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        moveToCircleButton.addTarget(self, action: #selector(moveToCircleButtonTapped), for: .touchUpInside)
        refreshAddressButton.addTarget(self, action: #selector(refreshAddressButtonTapped), for: .touchUpInside)
        
        
        // Add gesture recognizer to dismiss keyboard when tapping on the view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    private func populateFields() {
        nameTextField.text = place.name
        descriptionTextView.text = place.description
        
        // Category (the full list) and, on an "Other" place, your own label
        selectedCategory = place.category
        customCategoryTextField.text = place.category == .other ? place.customCategoryId : nil
        updateCategoryUI()

        // Show/hide refresh address button based on whether place has location
        refreshAddressButton.isHidden = place.location?.clLocation == nil
        
        // Parse address
        let addressComponents = place.address.components(separatedBy: ", ")
        if addressComponents.count > 0 {
            streetTextField.text = addressComponents[0]
        }
        if addressComponents.count > 1 {
            cityTextField.text = addressComponents[1]
        }
        if addressComponents.count > 2 {
            stateTextField.text = addressComponents[2]
        }
        if addressComponents.count > 3 {
            zipCodeTextField.text = addressComponents[3]
        }
        if addressComponents.count > 4 {
            countryTextField.text = addressComponents[4]
        }
        
        // Set privacy. A value this build doesn't recognise disables the
        // control instead of showing a narrower one we'd then save back.
        privacyPicker.select(place.privacy.option, listId: place.audienceListId)
        
        // The only note on a save is the private one; shared thoughts are comments
        notesTextView.text = place.privateNotes
        
        // Tags
        if let tags = place.tags {
            tagsTextField.text = tags.joined(separator: ", ")
        }
        
        websiteTextField.text = place.website
        phoneTextField.text = place.phone
        initialAddressText = addressBoxesText
        
    }
    
    // MARK: - Actions
    
    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }
    
    /// Prevents double-tapping the nav-bar Save from firing a second update
    private var isSaving = false

    @objc private func saveButtonTapped() {
        guard !isSaving else { return }

        // Validate required fields
        guard let name = nameTextField.text, !name.isEmpty else {
            presentAlert(title: "Error", message: "Please enter a name for the place")
            return
        }
        
        // Check if any fields have changed
        let hasChanges = checkForChanges()
        
        guard hasChanges else {
            dismiss(animated: true)
            return
        }
        
        // Special handling for Home/Work places
        if place.id == "home-place" || place.id == "work-place" {
            saveHomeOrWorkPlace()
            return
        }
        
        // Untouched boxes keep the stored address exactly
        let addressText = addressBoxesText == initialAddressText ? place.address : addressBoxesText

        // Shared details: only what changed, and only for the store's team or
        // an admin (the fields are locked for everyone else)
        let original = PlaceEditPlan.Details(
            name: place.name, address: place.address, category: place.category.rawValue,
            description: place.description, phone: place.phone, website: place.website,
            coordinate: place.location?.clLocation?.coordinate)
        let edited = PlaceEditPlan.Details(
            name: name, address: addressText, category: selectedCategory.rawValue,
            description: descriptionTextView.text, phone: phoneTextField.text, website: websiteTextField.text,
            coordinate: selectedLocation)
        let detailChanges = canEditDetails ? PlaceEditPlan.detailChanges(original: original, edited: edited) : [:]

        // Personal fields, on your own save only
        let privacy = privacyPicker.selectedPlacePrivacy ?? place.privacy
        let notes = PlaceEditPlan.clean(notesTextView.text)
        let tags = (tagsTextField.text ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let customCategory = selectedCategory == .other ? PlaceEditPlan.clean(customCategoryTextField.text) : nil
        let personalChanged = isOwnSave && (
            privacy != place.privacy
            || privacyPicker.selectedListId != place.audienceListId
            || notes != PlaceEditPlan.clean(place.privateNotes)
            || tags != (place.tags ?? [])
            || customCategory != PlaceEditPlan.clean(place.category == .other ? place.customCategoryId : nil))

        guard !detailChanges.isEmpty || personalChanged else {
            dismiss(animated: true)
            return
        }

        isSaving = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        let loading = showLoading(message: "Saving…")
        let fail: (Error) -> Void = { [weak self] error in
            loading.dismiss(animated: true) {
                guard let self else { return }
                self.isSaving = false
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                self.showError((error as? APIError)?.serverMessage ?? error.localizedDescription)
            }
        }
        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            // The place as everyone now sees it (shared details come from the
            // place record), for the page underneath
            PlaceService.shared.fetchPlaceById(id: self.place.id) { result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        if case .success(let updated) = result { self.delegate?.didUpdatePlace(updated) }
                        self.dismiss(animated: true)
                    }
                }
            }
        }
        let savePersonal: () -> Void = { [weak self] in
            guard let self else { return }
            guard personalChanged else { finish(); return }
            PlaceService.shared.updatePlace(
                id: self.place.id,
                customCategory: customCategory ?? "",
                privacy: privacy,
                audienceListId: self.privacyPicker.selectedListId,
                tags: tags,
                privateNotes: notes ?? ""
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: finish()
                    case .failure(let error): fail(error)
                    }
                }
            }
        }
        saveDetails(detailChanges, onError: fail, then: savePersonal)
    }

    private var addressBoxesText: String {
        [streetTextField.text, cityTextField.text, stateTextField.text, zipCodeTextField.text, countryTextField.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Shared details through the one path. A new address with an unmoved pin
    /// is geocoded first so the pin follows it; if that fails the address is
    /// still saved and the pin stays where it was.
    private func saveDetails(_ changes: [String: Any], onError: @escaping (Error) -> Void, then: @escaping () -> Void) {
        guard !changes.isEmpty else { then(); return }
        let placeId = globalPlaceId ?? place.globalPlaceId ?? place.id
        let send: ([String: Any]) -> Void = { body in
            PlaceDetailsService.shared.update(placeId: placeId, fields: body) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: then()
                    case .failure(let error): onError(error)
                    }
                }
            }
        }
        if let address = changes["address"] as? String, !address.isEmpty, changes["location"] == nil {
            PlaceService.shared.geocodeAddress(address) { result in
                var body = changes
                if case .success(let coordinate) = result {
                    body["location"] = ["type": "Point", "coordinates": [coordinate.longitude, coordinate.latitude]]
                }
                send(body)
            }
        } else {
            send(changes)
        }
    }

    @objc private func useCurrentLocationButtonTapped() {
        wantsCurrentLocation = true
        // Request location authorization if not already granted
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            showLocationPermissionAlert()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        @unknown default:
            break
        }
    }
    
    @objc private func refreshAddressButtonTapped() {
        let name = (nameTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = selectedLocation ?? place.location?.clLocation?.coordinate
        guard !name.isEmpty || pin != nil else {
            presentAlert(title: "No Location Available", message: "This place has no name or location to look up.")
            return
        }
        let loading = AlertPresenter.showLoading(message: "Looking up \(name.isEmpty ? "the address" : name) on Apple Maps…", from: self)

        // Find the BUSINESS by name near the pin (AppleVenueRefresh); the old
        // reverse-geocode of the pin only confirmed a wrong pin's address.
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .pointOfInterest
        if let pin {
            let span = AppleVenueRefresh.searchRadiusMeters * 2
            request.region = MKCoordinateRegion(center: pin, latitudinalMeters: span, longitudinalMeters: span)
        }
        MKLocalSearch(request: request).start { [weak self] response, _ in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    let items = response?.mapItems ?? []
                    let candidates = items.map { AppleVenueRefresh.Candidate(name: $0.name ?? "", coordinate: $0.placemark.coordinate) }
                    if !name.isEmpty, let index = AppleVenueRefresh.bestMatch(for: name, near: pin, in: candidates) {
                        self.offerAppleListing(items[index], pin: pin)
                    } else if let pin {
                        self.refreshStreetAddressOnly(at: pin, name: name)
                    } else {
                        self.presentAlert(title: "Not on Apple Maps", message: "Apple Maps doesn't list \(name) nearby.")
                    }
                }
            }
        }
    }

    /// Apple's listing for this business. At the pin: fill it in. Elsewhere:
    /// say where and how far, and move the pin only if they agree — a
    /// correction that moves the place is accepted, never silently applied.
    private func offerAppleListing(_ item: MKMapItem, pin: CLLocationCoordinate2D?) {
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let line = [street, placemark.locality].filter { !($0 ?? "").isEmpty }.compactMap { $0 }.joined(separator: ", ")
        let apply = { [weak self] in
            guard let self else { return }
            self.updateAddressFields(with: placemark)
            self.movePin(to: placemark.coordinate)
            if let phone = item.phoneNumber, !phone.isEmpty { self.phoneTextField.text = phone }
            if let url = item.url?.absoluteString, !url.isEmpty { self.websiteTextField.text = url }
            AlertPresenter.showSuccess("Updated from Apple Maps. Review it, then tap Save.", from: self)
        }
        let moved = pin.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            .distance(from: CLLocation(latitude: placemark.coordinate.latitude, longitude: placemark.coordinate.longitude)) } ?? 0
        guard moved > AppleVenueRefresh.sameSpotMeters else { apply(); return }
        let far = MKDistanceFormatter(); far.unitStyle = .abbreviated
        AlertPresenter.showConfirmation(
            title: "Apple Maps has it somewhere else",
            message: "\(item.name ?? "It") is at \(line.isEmpty ? "a different address" : line), \(far.string(fromDistance: moved)) from where the pin is now. Use Apple's address and move the pin there?",
            confirmTitle: "Use Apple's",
            from: self,
            onConfirm: apply
        )
    }

    /// No listing by that name: the street address under the pin, as before,
    /// saying so.
    private func refreshStreetAddressOnly(at pin: CLLocationCoordinate2D, name: String) {
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: pin.latitude, longitude: pin.longitude)) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let placemark = placemarks?.first, error == nil else {
                    self.presentAlert(title: "Error", message: "Could not find an address for this location.")
                    return
                }
                self.updateAddressFields(with: placemark)
                self.presentAlert(title: "Address from the pin",
                                  message: "Apple Maps doesn't list \(name.isEmpty ? "this place" : name) nearby, so this is the street address where the pin is. If the pin is in the wrong spot, tap the map where the place really is.")
            }
        }
    }

    private func movePin(to coordinate: CLLocationCoordinate2D) {
        selectedLocation = coordinate
        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = nameTextField.text
        mapView.addAnnotation(annotation)
        mapView.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600), animated: true)
    }

    @objc private func handleMapTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let touchPoint = gestureRecognizer.location(in: mapView)
        let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
        
        // Store the selected location
        self.selectedLocation = coordinate
        
        // Clear existing annotations
        mapView.removeAnnotations(mapView.annotations)
        
        // Add a new annotation
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "Selected Location"
        mapView.addAnnotation(annotation)
        
        // Get address from coordinates
        lookUpCurrentLocation(coordinate) { [weak self] placemark in
            guard let self = self else { return }
            guard let placemark = placemark else { return }
            
            DispatchQueue.main.async {
                self.updateAddressFields(with: placemark)
            }
        }
    }
    
    private func saveHomeOrWorkPlace() {
        // Format the address string
        let formattedAddress = [streetTextField.text, cityTextField.text, stateTextField.text, zipCodeTextField.text, countryTextField.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        
        guard !formattedAddress.isEmpty else {
            presentAlert(title: "Error", message: "Please enter an address")
            return
        }
        
        // Save to UserDefaults
        let key = place.id == "home-place" ? "userHomeAddress" : "userWorkAddress"
        UserDefaults.standard.set(formattedAddress, forKey: key)
        
        // FIXME: Need to update this to handle Place creation properly
        // For now, just dismiss without updating since Place no longer has a direct initializer
        // This only affects local home/work places which are a special case
        dismiss(animated: true)
        
        /*
        // Create updated place object
        let updatedPlace = Place(
            id: place.id,
            name: nameTextField.text ?? place.name,
            description: descriptionTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : descriptionTextView.text,
            address: formattedAddress,
            location: place.location, // Keep existing location
            website: websiteTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true ? nil : websiteTextField.text,
            phone: phoneTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true ? nil : phoneTextField.text,
            googlePlaceId: place.googlePlaceId,
            photos: place.photos,
            category: place.category,
            rating: place.rating,
            userRatingsTotal: place.userRatingsTotal,
            notes: nil,
            privateNotes: notesTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesTextView.text,
            publicNotes: nil,
            tags: place.tags,
            reviews: place.reviews,
            openingHours: place.openingHours,
            priceLevel: place.priceLevel,
            circleId: place.circleId,
            addedBy: place.addedBy,
            addedByUser: place.addedByUser,
            privacy: place.privacy,
            createdAt: place.createdAt,
            updatedAt: Date()
        )
        
        // Notify delegate and dismiss
        delegate?.didUpdatePlace(updatedPlace)
        dismiss(animated: true)
        */
    }
    
    @objc private func moveToCircleButtonTapped() {
        let circleSelectionVC = CircleSelectionViewController(excludedCircleId: place.circleId)
        circleSelectionVC.delegate = self
        present(circleSelectionVC, animated: true)
    }
    
    @objc private func deleteButtonTapped() {
        // Special handling for Home/Work places
        if place.id == "home-place" || place.id == "work-place" {
            let alert = UIAlertController(
                title: "Clear \(place.name)",
                message: "Are you sure you want to clear your \(place.name.lowercased()) address?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
                self?.clearHomeOrWorkPlace()
            })
            
            present(alert, animated: true)
            return
        }
        
        let alert = UIAlertController(
            title: "Unsave Place",
            message: "Take \(place.name) out of your circles? Your notes, photos and rating on it go too. This can't be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Unsave", style: .destructive) { [weak self] _ in
            self?.deletePlace()
        })
        
        present(alert, animated: true)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    
    // MARK: - Photo Methods
    
    
    
    
    
    
    // MARK: - Helper Methods
    
    private func checkForChanges() -> Bool {
        // Check name
        if nameTextField.text != place.name { return true }
        
        // Check description
        let currentDescription = descriptionTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalDescription = place.description ?? ""
        if currentDescription != originalDescription { return true }
        
        // Check category
        if selectedCategory != place.category { return true }
        
        // Check custom category if "Other" is selected
        if place.category == .other {
            let currentCustomCategory = customCategoryTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let originalCustomCategory = place.customCategoryId ?? ""
            if currentCustomCategory != originalCustomCategory { return true }
        }
        
        // Check address
        let formattedAddress = [streetTextField.text, cityTextField.text, stateTextField.text, zipCodeTextField.text, countryTextField.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        if formattedAddress != place.address { return true }
        
        // Check privacy
        // A locked picker can't have changed anything, so it isn't "dirty".
        if let picked = privacyPicker.selectedPlacePrivacy, picked != place.privacy { return true }
        
        // Check notes
        let currentNotes = notesTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalNotes = place.publicNotes ?? place.notes ?? ""
        if currentNotes != originalNotes { return true }
        
        // Check tags
        let currentTags = tagsTextField.text?.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? []
        let originalTags = place.tags ?? []
        if currentTags != originalTags { return true }
        
        // Check website
        let currentWebsite = websiteTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalWebsite = place.website ?? ""
        if currentWebsite != originalWebsite { return true }
        
        // Check phone
        let currentPhone = phoneTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalPhone = place.phone ?? ""
        if currentPhone != originalPhone { return true }
        
        
        return false
    }
    
    private func clearHomeOrWorkPlace() {
        // Clear from UserDefaults
        let key = place.id == "home-place" ? "userHomeAddress" : "userWorkAddress"
        UserDefaults.standard.removeObject(forKey: key)
        
        // Notify delegate and dismiss
        delegate?.didDeletePlace(place.id)
        dismiss(animated: true)
    }
    
    private func deletePlace() {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Unsaving Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        PlaceService.shared.deletePlace(id: place.id) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(_):
                        self?.delegate?.didDeletePlace(self?.place.id ?? "")
                        self?.dismiss(animated: true)
                        
                    case .failure(let error):
                        self?.presentAlert(title: "Error", message: error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private func showLocationPermissionAlert() {
        let alert = UIAlertController(
            title: "Location Access Required",
            message: "Please allow access to your location in Settings to use this feature.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func lookUpCurrentLocation(_ coordinate: CLLocationCoordinate2D, completionHandler: @escaping (CLPlacemark?) -> Void) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if error == nil {
                let placemark = placemarks?[0]
                completionHandler(placemark)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    private func updateAddressFields(with placemark: CLPlacemark) {
        streetTextField.text = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        cityTextField.text = placemark.locality
        stateTextField.text = placemark.administrativeArea
        zipCodeTextField.text = placemark.postalCode
        countryTextField.text = placemark.country
    }
    
    private func presentAlert(title: String, message: String, completion: ((UIAlertAction) -> Void)? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: completion))
        present(alertController, animated: true)
    }
}

// MARK: - CLLocationManagerDelegate

// MARK: - PHPickerViewControllerDelegate

extension EditPlaceViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let providers = results.map(\.itemProvider).filter { $0.canLoadObject(ofClass: UIImage.self) }
        guard !providers.isEmpty else { return }
        // Load in parallel, keep the order they were picked in
        var images = [UIImage?](repeating: nil, count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    images[index] = object as? UIImage
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.uploadToLibrary(images.compactMap { $0 })
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension EditPlaceViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Stop updating location
        manager.stopUpdatingLocation()
        
        // Store user's location
        self.selectedLocation = location.coordinate
        
        // Center map on user's location
        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        mapView.setRegion(region, animated: true)
        
        // Clear existing annotations
        mapView.removeAnnotations(mapView.annotations)
        
        // Add a new annotation
        let annotation = MKPointAnnotation()
        annotation.coordinate = location.coordinate
        annotation.title = "Current Location"
        mapView.addAnnotation(annotation)
        
        // Get address from coordinates
        lookUpCurrentLocation(location.coordinate) { [weak self] placemark in
            guard let self = self else { return }
            guard let placemark = placemark else { return }
            
            DispatchQueue.main.async {
                self.updateAddressFields(with: placemark)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.debug("Location manager failed with error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // This fires on delegate assignment at screen open — only act when
        // the user actually tapped "Use Current Location"
        guard wantsCurrentLocation else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            showLocationPermissionAlert()
        default:
            break
        }
    }
}

// MARK: - CircleSelectionDelegate

extension EditPlaceViewController: CircleSelectionDelegate {
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Moving Place", message: "Moving \(place.name) to \(circle.name)...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Perform the move
        PlaceService.shared.movePlaceToCircle(placeId: place.id, targetCircleId: circle.id) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let updatedPlace):
                        // Update the local place object
                        self.place = updatedPlace
                        
                        // Notify delegate about the update
                        self.delegate?.didUpdatePlace(updatedPlace)
                        
                        // Show success message
                        let successAlert = UIAlertController(
                            title: "Success",
                            message: "\(self.place.name) has been moved to \(circle.name)",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                            self.dismiss(animated: true)
                        })
                        self.present(successAlert, animated: true)
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Failed to move place: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        }
    }
    
    func circleSelectionViewControllerDidCancel(_ controller: CircleSelectionViewController) {
        // User cancelled, nothing to do
    }
}