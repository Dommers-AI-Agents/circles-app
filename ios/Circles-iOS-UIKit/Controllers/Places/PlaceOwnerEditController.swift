import UIKit

/// The place-page views a verified venue owner edits in place.
struct PlaceOwnerEditableFields {
    let nameLabel: UILabel
    let addressLabel: UILabel
    let categoryLabel: UILabel
    let categoryEditButton: UIButton
    let descriptionLabel: UILabel
    let aboutTitleLabel: UILabel
    /// The About card's stack; the owner-only description/contact rows are
    /// appended here.
    let aboutStackView: UIStackView
}

/// What the owner editor needs from the place page it decorates.
protocol PlaceOwnerEditControllerDelegate: AnyObject {
    /// The place currently rendered (the editor never caches it).
    var placeForOwnerEdit: Place { get }
    /// Address is the one deliberate flow — a typo silently moves the pin,
    /// so it reuses the page's map-confirmed update sheet.
    func ownerEditRequestsAddressUpdate()
    /// A field save landed: adopt the server's copy and re-render the page.
    func ownerEditDidUpdatePlace(_ place: Place)
    /// The owner rows appeared/disappeared; the About card's collapse must
    /// count them as content.
    func ownerEditDidChangeAboutContent()
    /// Owner preview flipped between owner chrome and the customer view.
    func ownerEditDidToggleCustomerView(_ viewingAsCustomer: Bool)
}

/// Owner tap-to-edit for a place page. The owner's place page IS the
/// editor: tap a field to arm it, commit to save. Every save goes through
/// the owner-unlocked updatePlace path, so propagateVenueUpdates fans the
/// change out to every saver's copy.
///
/// Owns the owner state (verified owner, customer preview, installed
/// affordances) and the edit flows; the page keeps its views and re-renders
/// through the delegate. Extracted from PlaceDetailViewController.
final class PlaceOwnerEditController: NSObject {
    typealias Host = UIViewController & PlaceOwnerEditControllerDelegate

    private let fields: PlaceOwnerEditableFields
    private weak var host: Host?

    /// Verified owner of this venue (from getVenueByPlace). Owners can edit
    /// venue fields from any save of their place — the backend restricts
    /// their update to venue fields.
    var isVenueOwner = false
    /// Owner preview mode: render the page exactly as a customer sees it.
    private(set) var viewingAsCustomer = false
    /// Gestures are installed once; the ✎ affordances and the owner-only
    /// rows come and go with customer preview.
    private var decorated = false
    private var contactEditRow: UILabel?
    private var descriptionEditRow: UILabel?

    init(fields: PlaceOwnerEditableFields, host: Host) {
        self.fields = fields
        self.host = host
        super.init()
    }

    private var place: Place? { host?.placeForOwnerEdit }

    /// Whether an owner-only row is showing (it counts as About-card content).
    var hasVisibleOwnerRows: Bool {
        (contactEditRow?.isHidden == false) || (descriptionEditRow?.isHidden == false)
    }

    // MARK: - Arming

    /// Installs the tap-to-edit gestures once the viewer is a verified owner.
    func decorateIfNeeded() {
        guard isVenueOwner, !decorated else { return }
        decorated = true

        fields.nameLabel.isUserInteractionEnabled = true
        fields.nameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(nameTapped)))

        fields.addressLabel.isUserInteractionEnabled = true
        fields.addressLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(addressTapped)))

        fields.categoryLabel.isUserInteractionEnabled = true
        fields.categoryLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(categoryTapped)))
        // The pencil next to the category chip opened the whole legacy edit
        // screen — repoint it at the category picker it sits beside
        fields.categoryEditButton.removeTarget(nil, action: nil, for: .allEvents)
        fields.categoryEditButton.addTarget(self, action: #selector(categoryTapped), for: .touchUpInside)

        // The description's link-tap gesture is for customers tapping the
        // Phone/Website lines; the owner tapping their own description means
        // "edit it"
        fields.descriptionLabel.gestureRecognizers?.forEach { fields.descriptionLabel.removeGestureRecognizer($0) }
        fields.descriptionLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(descriptionTapped)))
        fields.aboutTitleLabel.isUserInteractionEnabled = true
        fields.aboutTitleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(descriptionTapped)))

        refreshAffordances()
    }

    /// ✎ affordances (and the owner-only rows) appear in owner mode and
    /// disappear in customer preview. Idempotent — safe after re-renders.
    func refreshAffordances() {
        guard decorated, let place = place else { return }
        let editing = !viewingAsCustomer

        fields.nameLabel.text = editing ? "\(place.name) ✎" : place.name
        fields.addressLabel.text = editing ? "\(place.address) ✎" : place.address
        // The category pencil is normally gated on save-edit rights — the
        // venue owner always gets it (it opens the category picker)
        fields.categoryEditButton.isHidden = !editing

        // Explicit, labeled owner rows in the About card — a bare paragraph
        // tap was invisible, and one trailing ✎ read as "website only"
        if editing {
            let descRow = descriptionEditRow ?? {
                let label = makeRowLabel(action: #selector(descriptionTapped))
                fields.aboutStackView.addArrangedSubview(label)
                descriptionEditRow = label
                return label
            }()
            let hasDescription = !(place.description ?? "").isEmpty
            descRow.text = hasDescription ? "📝 Edit description ✎" : "📝 Add a description ✎"
            descRow.isHidden = false

            let contactRow = contactEditRow ?? {
                let label = makeRowLabel(action: #selector(contactTapped))
                fields.aboutStackView.addArrangedSubview(label)
                contactEditRow = label
                return label
            }()
            let phoneText = (place.phone ?? "").isEmpty ? "Add phone" : place.phone!
            let webText = (place.website ?? "").isEmpty ? "Add website" : place.website!
            contactRow.text = "📞 \(phoneText) ✎\n🌐 \(webText) ✎"
            contactRow.isHidden = false
        } else {
            descriptionEditRow?.isHidden = true
            contactEditRow?.isHidden = true
        }

        // The About card may have been collapsed for lack of content — the
        // owner's edit affordances count as content
        host?.ownerEditDidChangeAboutContent()
    }

    /// Flip the whole page between owner chrome and the exact customer view.
    func toggleViewAsCustomer() {
        viewingAsCustomer.toggle()
        host?.ownerEditDidToggleCustomerView(viewingAsCustomer)
        refreshAffordances()
    }

    private func makeRowLabel(action: Selector) -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.primary
        label.numberOfLines = 0
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: action))
        return label
    }

    // MARK: - Description text

    /// The description is PROSE — phone/website are separate fields with
    /// their own editor row, so their legacy embedded "Phone:"/"Website:"
    /// lines never appear in (or survive) the description editor.
    static func strippingContactLines(_ text: String?) -> String {
        guard let text = text else { return "" }
        return text
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("Phone:") && !trimmed.hasPrefix("Website:")
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Field editors

    private var canEdit: Bool { isVenueOwner && !viewingAsCustomer }

    @objc private func nameTapped() {
        guard canEdit, let place = place else { return }
        promptText(title: "Store Name", initial: place.name, keyboard: .default) { [weak self] value in
            guard !value.isEmpty else { return }
            self?.save(name: value)
        }
    }

    @objc private func addressTapped() {
        guard canEdit else { return }
        host?.ownerEditRequestsAddressUpdate()
    }

    @objc private func categoryTapped() {
        guard canEdit, let host = host else { return }
        let categories: [PlaceCategory] = [.restaurant, .cafe, .bar, .hotel, .retail, .service, .attraction, .other]
        let actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = categories.map { category in
            (title: category.displayName, style: .default, handler: { [weak self] in
                self?.save(category: category)
            })
        }
        AlertPresenter.showActionSheet(title: "Category", actions: actions, from: host)
    }

    @objc private func descriptionTapped() {
        guard canEdit, let host = host, let place = place else { return }
        // A half-sheet with the text view pinned to the keyboard — an inline
        // in-card editor kept losing the fight with keyboard geometry
        let editor = OwnerDescriptionEditorViewController()
        editor.initialText = Self.strippingContactLines(place.description)
        editor.onSave = { [weak self] text in
            self?.save(description: Self.strippingContactLines(text))
        }
        let nav = UINavigationController(rootViewController: editor)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        host.present(nav, animated: true)
    }

    @objc private func contactTapped() {
        guard canEdit, let host = host, let place = place else { return }
        AlertPresenter.showMultiFieldInput(
            title: "Contact Info",
            message: nil,
            fields: [
                (placeholder: "Phone", keyboardType: .phonePad, initialText: place.phone),
                (placeholder: "Website", keyboardType: .URL, initialText: place.website)
            ],
            confirmTitle: "Save",
            from: host
        ) { [weak self] values in
            let phone = (values.count > 0 ? values[0] : nil)?.trimmingCharacters(in: .whitespaces) ?? ""
            let website = (values.count > 1 ? values[1] : nil)?.trimmingCharacters(in: .whitespaces) ?? ""
            self?.save(website: website, phone: phone)
        }
    }

    private func promptText(title: String, initial: String?, keyboard: UIKeyboardType, onSave: @escaping (String) -> Void) {
        guard let host = host else { return }
        AlertPresenter.showTextInput(
            title: title,
            initialText: initial,
            keyboardType: keyboard,
            confirmTitle: "Save",
            from: host
        ) { value in
            onSave((value ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Save

    private func save(
        name: String? = nil,
        description: String? = nil,
        category: PlaceCategory? = nil,
        website: String? = nil,
        phone: String? = nil
    ) {
        guard let host = host, let place = place else { return }
        let loading = AlertPresenter.showLoading(message: "Saving...", from: host)
        PlaceService.shared.updatePlace(
            id: place.id,
            name: name,
            description: description,
            category: category,
            website: website,
            phone: phone
        ) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self, let host = self.host else { return }
                    switch result {
                    case .success(let updated):
                        host.ownerEditDidUpdatePlace(updated)
                        self.refreshAffordances()
                    case .failure(let error):
                        host.showError(error)
                    }
                }
            }
        }
    }
}
