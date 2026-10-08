import UIKit

/// Super-users: printed-postcard specials ("$1.99 today only", Wes
/// 2026-10-08). The server keeps the schedule and decides the price; this
/// lists what's running or coming up, adds one, and ends one early.
final class PostcardSpecialsViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate {

    struct Special: Decodable {
        let id: String
        let priceCents: Int
        let label: String
        let startsAt: String
        let endsAt: String
    }
    private struct ListResponse: Decodable {
        let specials: [Special]
        let regularPriceCents: Int
        let minPriceCents: Int
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var specials: [Special] = []
    private var regularPriceCents = 399
    private var minPriceCents = 149

    override var enablesPullToRefresh: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Postcard Specials"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.refreshControl = refreshControl
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func loadData(completion: (() -> Void)? = nil) {
        APIService.shared.request(endpoint: "widgets/postcard/mail/specials", method: .get) { [weak self] (result: Result<ListResponse, APIError>) in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let list):
                    self.specials = list.specials
                    self.regularPriceCents = list.regularPriceCents
                    self.minPriceCents = list.minPriceCents
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(specials.count, 1) }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Regular price \(Self.dollars(regularPriceCents)). A special can go as low as \(Self.dollars(minPriceCents)). "
            + "People who saw a special keep that price for 2 hours, even if it ends while they write their card. Tap a special to end it now."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        guard !specials.isEmpty else {
            cell.textLabel?.text = "No specials yet"
            cell.detailTextLabel?.text = "Tap + to run one, like $1.99 today only."
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
            return cell
        }
        let special = specials[indexPath.row]
        cell.textLabel?.text = "\(Self.dollars(special.priceCents)) · \(special.label)"
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cell.detailTextLabel?.text = Self.window(special)
        cell.detailTextLabel?.textColor = Self.isOver(special) ? .tertiaryLabel : .secondaryLabel
        cell.selectionStyle = Self.isOver(special) ? .none : .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard specials.indices.contains(indexPath.row) else { return }
        let special = specials[indexPath.row]
        guard !Self.isOver(special) else { return }
        showConfirmation(title: "End this special?",
                         message: "\(Self.dollars(special.priceCents)) · \(special.label) stops now; postcards go back to \(Self.dollars(regularPriceCents)).",
                         confirmTitle: "End now", isDestructive: true) { [weak self] in
            self?.end(special)
        }
    }

    private func end(_ special: Special) {
        APIService.shared.request(endpoint: "widgets/postcard/mail/specials/\(special.id)", method: .delete) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                if case .failure(let error) = result { self?.showError(error) }
                self?.loadData()
            }
        }
    }

    @objc private func addTapped() {
        let form = AddPostcardSpecialViewController(regularPriceCents: regularPriceCents, minPriceCents: minPriceCents)
        form.onSaved = { [weak self] in self?.loadData() }
        navigationController?.pushViewController(form, animated: true)
    }

    // MARK: - Words

    static func dollars(_ cents: Int) -> String { String(format: "$%.2f", Double(cents) / 100) }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func date(_ s: String) -> Date? { iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) }
    static func isOver(_ s: Special) -> Bool { (date(s.endsAt) ?? .distantPast) <= Date() }

    static func window(_ s: Special) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        guard let start = date(s.startsAt), let end = date(s.endsAt) else { return "" }
        if end <= Date() { return "Ended \(f.string(from: end))" }
        if start > Date() { return "Starts \(f.string(from: start)) · ends \(f.string(from: end))" }
        return "Running now · ends \(f.string(from: end))"
    }
}

/// Price, label and window for a new special.
final class AddPostcardSpecialViewController: BaseViewController {
    var onSaved: (() -> Void)?
    private let regularPriceCents: Int
    private let minPriceCents: Int

    private let priceField = UITextField()
    private let labelField = UITextField()
    private let startPicker = UIDatePicker()
    private let endPicker = UIDatePicker()
    private lazy var saveButton = UIButton.primaryButton(title: "Start special")

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    init(regularPriceCents: Int, minPriceCents: Int) {
        self.regularPriceCents = regularPriceCents
        self.minPriceCents = minPriceCents
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Special"
        view.backgroundColor = .systemGroupedBackground

        priceField.text = "1.99"
        priceField.keyboardType = .decimalPad
        priceField.borderStyle = .roundedRect
        priceField.font = .systemFont(ofSize: 22, weight: .bold)
        labelField.text = "Today only"
        labelField.placeholder = "Label people see"
        labelField.borderStyle = .roundedRect
        labelField.autocapitalizationType = .sentences

        let calendar = Calendar.current
        startPicker.date = Date()
        endPicker.date = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date().addingTimeInterval(86400)
        [startPicker, endPicker].forEach { $0.datePickerMode = .dateAndTime; $0.preferredDatePickerStyle = .compact; $0.minimumDate = Date().addingTimeInterval(-60) }

        let stack = UIStackView(arrangedSubviews: [
            caption("Price (regular \(PostcardSpecialsViewController.dollars(regularPriceCents)), lowest \(PostcardSpecialsViewController.dollars(minPriceCents)))"),
            priceField,
            caption("Label"),
            labelField,
            row("Starts", startPicker),
            row("Ends", endPicker),
            saveButton
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(24, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            priceField.heightAnchor.constraint(equalToConstant: 48),
            labelField.heightAnchor.constraint(equalToConstant: 44)
        ])
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        setupKeyboardHandling(dismissOnTap: true)
    }

    private func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private func row(_ title: String, _ picker: UIDatePicker) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .medium)
        let row = UIStackView(arrangedSubviews: [label, picker])
        row.distribution = .equalSpacing
        return row
    }

    @objc private func saveTapped() {
        let text = (priceField.text ?? "").replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ".")
        guard let dollars = Double(text.trimmingCharacters(in: .whitespaces)) else {
            return showError("Enter a price, like 1.99.")
        }
        let cents = Int((dollars * 100).rounded())
        guard cents >= minPriceCents else {
            return showError("A special can't go below \(PostcardSpecialsViewController.dollars(minPriceCents)).")
        }
        guard cents < regularPriceCents else {
            return showError("A special has to be under the regular \(PostcardSpecialsViewController.dollars(regularPriceCents)).")
        }
        guard endPicker.date > startPicker.date, endPicker.date > Date() else {
            return showError("Pick an end time after the start.")
        }
        let iso = ISO8601DateFormatter()
        let body: [String: Any] = [
            "priceCents": cents,
            "label": labelField.text ?? "",
            "startsAt": iso.string(from: startPicker.date),
            "endsAt": iso.string(from: endPicker.date)
        ]
        saveButton.isEnabled = false
        APIService.shared.request(endpoint: "widgets/postcard/mail/specials", method: .post, body: body) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveButton.isEnabled = true
                switch result {
                case .success:
                    self.onSaved?()
                    self.navigationController?.popViewController(animated: true)
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}
