import UIKit

/// Edit the account's brand storefront — the card shown on the profile.
/// Business-standing is enforced server-side; this screen is reached from
/// the owner venues screen (and the card's pencil on your own profile).
class StorefrontEditViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }

    /// Prefill from the current values when the caller has them
    var initialStorefront: StorefrontInfo?
    var initialFindUsAtCircleId: String?
    var onSaved: (() -> Void)?

    private var selectedCircle: Circle?
    private var userCircles: [Circle] = []

    private let scrollView = UIScrollView()

    private let enabledSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.onTintColor = Constants.Colors.primary
        toggle.isOn = true
        return toggle
    }()

    private lazy var nameField = makeField(placeholder: "Business name (required)")
    private lazy var websiteField = makeField(placeholder: "Website (optional)", keyboard: .URL)
    private lazy var catalogField = makeField(placeholder: "Catalog / shop link (optional)", keyboard: .URL)
    private lazy var contactField = makeField(placeholder: "Contact email (optional)", keyboard: .emailAddress)

    private let aboutTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = Constants.Colors.separator.cgColor
        textView.backgroundColor = Constants.Colors.secondaryBackground
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        return textView
    }()

    private lazy var circleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Choose a circle…", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        button.contentHorizontalAlignment = .leading
        button.setTitleColor(Constants.Colors.label, for: .normal)
        button.backgroundColor = Constants.Colors.secondaryBackground
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        button.addTarget(self, action: #selector(chooseCircleTapped), for: .touchUpInside)
        return button
    }()

    private lazy var saveButton: UIButton = {
        let button = UIButton.primaryButton(title: "Save Storefront")
        button.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Brand Storefront"
        view.backgroundColor = Constants.Colors.background
        buildForm()
        prefill()
        loadCircles()
    }

    private func makeField(placeholder: String, keyboard: UIKeyboardType = .default) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.font = UIFont.systemFont(ofSize: 16)
        field.borderStyle = .roundedRect
        field.backgroundColor = Constants.Colors.secondaryBackground
        field.autocapitalizationType = keyboard == .default ? .words : .none
        field.autocorrectionType = .no
        field.keyboardType = keyboard
        return field
    }

    private func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = Constants.Colors.secondaryLabel
        return label
    }

    private func buildForm() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let enabledRow = UIStackView(arrangedSubviews: [caption("Show storefront on my profile"), UIView(), enabledSwitch])
        enabledRow.axis = .horizontal
        enabledRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [
            enabledRow,
            caption("Business name"), nameField,
            caption("About"), aboutTextView,
            caption("Links"), websiteField, catalogField, contactField,
            caption("\"Find us at\" circle — your conference & event schedule"), circleButton,
            saveButton
        ])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(18, after: enabledRow)
        stack.setCustomSpacing(18, after: aboutTextView)
        stack.setCustomSpacing(18, after: contactField)
        stack.setCustomSpacing(24, after: circleButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])
    }

    private func prefill() {
        guard let storefront = initialStorefront else { return }
        nameField.text = storefront.businessName
        aboutTextView.text = storefront.about
        websiteField.text = storefront.website
        catalogField.text = storefront.catalogUrl
        contactField.text = storefront.contactEmail
    }

    private func loadCircles() {
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, case .success(let circles) = result else { return }
                self.userCircles = circles
                if let selectedId = self.initialFindUsAtCircleId,
                   let match = circles.first(where: { $0.id == selectedId }) {
                    self.selectedCircle = match
                    self.circleButton.setTitle("📍 \(match.name)", for: .normal)
                }
            }
        }
    }

    @objc private func chooseCircleTapped() {
        // User's own order (same as the profile grid)
        let picker = CirclePickerViewController(circles: userCircles)
        picker.onCircleSelected = { [weak self] circle in
            self?.selectedCircle = circle
            self?.circleButton.setTitle("📍 \(circle.name)", for: .normal)
        }
        let navController = UINavigationController(rootViewController: picker)
        navController.modalPresentationStyle = .pageSheet
        if let sheet = navController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navController, animated: true)
    }

    @objc private func saveTapped() {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if enabledSwitch.isOn && name.isEmpty {
            showError("A business name is required to show the storefront")
            return
        }

        var fields: [String: Any] = [
            "enabled": enabledSwitch.isOn,
            "businessName": name,
            "about": aboutTextView.text.trimmingCharacters(in: .whitespacesAndNewlines),
            "website": (websiteField.text ?? "").trimmingCharacters(in: .whitespaces),
            "catalogUrl": (catalogField.text ?? "").trimmingCharacters(in: .whitespaces),
            "contactEmail": (contactField.text ?? "").trimmingCharacters(in: .whitespaces)
        ]
        if let circle = selectedCircle {
            fields["findUsAtCircleId"] = circle.id
        }

        saveButton.setLoading(true)
        RewardsService.shared.updateStorefront(fields) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.saveButton.setLoading(false)
                switch result {
                case .success:
                    self.onSaved?()
                    self.showSuccess("Storefront saved")
                    self.navigationController?.popViewController(animated: true)
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}
