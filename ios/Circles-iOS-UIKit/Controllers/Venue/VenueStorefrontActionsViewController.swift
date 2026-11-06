import UIKit

/// The store's buttons on its place page: Menu, Reserve, Order, Catering,
/// Book — each a link the owner already has (their menu page, OpenTable,
/// Toast) — and the automatic ones (Delivery, Reservations, Ride) they can
/// turn off. Free for every claimed venue: a working Reserve button helps the
/// customer whoever is paying. Ranked on the page by PlaceActionPlanner.
final class VenueStorefrontActionsViewController: BaseViewController {
    private let venueId: String
    private var actions: StorefrontActions
    var onSaved: ((VenueStorefront) -> Void)?

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private struct Field { let key: String; let title: String; let hint: String; let icon: String }
    private let fields: [Field] = [
        Field(key: "menu", title: "Menu", hint: "Your online menu page", icon: "menucard"),
        Field(key: "reserve", title: "Reserve a table", hint: "OpenTable, Resy, Tock…", icon: "calendar.badge.clock"),
        Field(key: "order", title: "Order online", hint: "Toast, Square, DoorDash…", icon: "bag"),
        Field(key: "catering", title: "Catering & events", hint: "Your catering page or inquiry form", icon: "fork.knife"),
        Field(key: "book", title: "Book an appointment", hint: "Booking or scheduling link", icon: "calendar")
    ]
    private var textFields: [String: UITextField] = [:]
    /// The automatic buttons, on unless the owner turned them off
    private let automatic: [(key: String, title: String, detail: String)] = [
        ("delivery", "Delivery", "DoorDash and Uber Eats"),
        ("reserve", "Reservations", "OpenTable (your Reserve link above replaces it)"),
        ("ride", "Ride", "Uber and Lyft, for people more than 3 miles away")
    ]
    private var switches: [String: UISwitch] = [:]
    private lazy var saveButton = UIButton.primaryButton(title: "Save buttons")

    init(venueId: String, actions: StorefrontActions?) {
        self.venueId = venueId
        self.actions = actions ?? StorefrontActions()
        super.init(nibName: nil, bundle: nil)
        title = "Buttons"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32)
        ])

        let intro = UILabel()
        intro.text = "These show as buttons on your store's page. Leave one blank to hide it. Menu opens your in-app menu when you have one, then this link, then your website."
        intro.font = .systemFont(ofSize: 14)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0
        stack.addArrangedSubview(intro)

        for field in fields {
            stack.addArrangedSubview(makeRow(field))
        }
        let autoHeader = UILabel()
        autoHeader.text = "Automatic buttons"
        autoHeader.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(autoHeader)
        let hidden = Set(actions.hide ?? [])
        for item in automatic {
            stack.addArrangedSubview(makeSwitchRow(item, isOn: !hidden.contains(item.key)))
        }
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        stack.addArrangedSubview(saveButton)
    }

    private func makeRow(_ field: Field) -> UIView {
        let box = UIStackView()
        box.axis = .vertical
        box.spacing = 6
        let title = UILabel()
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .label
        let attachment = NSTextAttachment(image: UIImage(systemName: field.icon)?.withTintColor(Constants.Colors.primary) ?? UIImage())
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(string: "  \(field.title)"))
        title.attributedText = text
        let tf = UITextField()
        tf.placeholder = field.hint
        tf.text = current(field.key)
        tf.keyboardType = .URL
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.clearButtonMode = .whileEditing
        tf.borderStyle = .roundedRect
        tf.font = .systemFont(ofSize: 15)
        tf.returnKeyType = .done
        tf.delegate = self
        textFields[field.key] = tf
        box.addArrangedSubview(title)
        box.addArrangedSubview(tf)
        return box
    }

    private func makeSwitchRow(_ item: (key: String, title: String, detail: String), isOn: Bool) -> UIView {
        let title = UILabel()
        title.text = item.title
        title.font = .systemFont(ofSize: 15)
        let detail = UILabel()
        detail.text = item.detail
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        let labels = UIStackView(arrangedSubviews: [title, detail])
        labels.axis = .vertical
        labels.spacing = 2
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = Constants.Colors.primary
        switches[item.key] = toggle
        let row = UIStackView(arrangedSubviews: [labels, toggle])
        row.alignment = .center
        row.spacing = 12
        return row
    }

    private func current(_ key: String) -> String? {
        switch key {
        case "menu": return actions.menu
        case "reserve": return actions.reserve
        case "order": return actions.order
        case "catering": return actions.catering
        default: return actions.book
        }
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        // "resy.com/x" is what people type; the server wants a web address.
        func clean(_ key: String) -> String? {
            guard var s = textFields[key]?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            if !s.lowercased().hasPrefix("http") { s = "https://" + s }
            return s
        }
        var next = StorefrontActions()
        next.reserve = clean("reserve")
        next.order = clean("order")
        next.catering = clean("catering")
        next.book = clean("book")
        next.menu = clean("menu")
        next.hide = automatic.map(\.key).filter { switches[$0]?.isOn == false }
        saveButton.isEnabled = false
        RewardsService.shared.updateStorefrontActions(venueId: venueId, actions: next) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveButton.isEnabled = true
                switch result {
                case .success(let storefront):
                    self.actions = storefront.actions ?? StorefrontActions()
                    self.onSaved?(storefront)
                    self.showSuccess("Buttons saved")
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}

extension VenueStorefrontActionsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
}
