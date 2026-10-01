import UIKit

/// The owner sets the store's opening hours for the place page: one row per
/// day, open/closed plus two times. Saving replaces the whole week, and
/// owner-set hours are never overwritten by a Google refresh.
final class VenueHoursViewController: BaseViewController {

    /// The place whose hours these are. Saved through the shared-details path
    /// (PlaceDetailsService) like every other detail, so it works on any place
    /// an owner or admin can edit — with or without a store record.
    private let placeId: String
    private var draft = VenueHoursDraft(existing: [])
    /// Called with the saved hours so the store page can refresh its summary
    var onSaved: (([OpeningHour]) -> Void)?

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 60
        table.allowsSelection = false
        return table
    }()

    init(placeId: String) {
        self.placeId = placeId
        super.init(nibName: nil, bundle: nil)
    }

    /// The store screens' entry point; the store id no longer matters to the save.
    convenience init(venueId: String, placeId: String) {
        self.init(placeId: placeId)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Opening Hours"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveTapped))
        navigationItem.rightBarButtonItem?.isEnabled = false

        tableView.dataSource = self
        tableView.register(DayHoursCell.self, forCellReuseIdentifier: DayHoursCell.reuseId)
        view.addSubview(tableView)
        view.sendSubviewToBack(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func loadData(completion: (() -> Void)? = nil) {
        GlobalPlaceService.shared.getGlobalPlace(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                completion?()
                // A failed read still lets the owner type the week in from 9–5
                if case .success(let response) = result {
                    self.draft = VenueHoursDraft(hours: response.globalPlace.googleData?.openingHours)
                }
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                self.tableView.reloadData()
            }
        }
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        if let problem = draft.problem {
            showError(problem)
            return
        }
        let loading = AlertPresenter.showLoading(message: "Saving hours...", from: self)
        PlaceDetailsService.shared.update(placeId: placeId, fields: draft.requestBody) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let saved):
                        self.onSaved?(saved.openingHours ?? [])
                        self.navigationController?.popViewController(animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
}

extension VenueHoursViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        draft.days.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "These hours show on your place page and replace what Google had. A closing time earlier than the opening time means you close after midnight."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DayHoursCell.reuseId, for: indexPath) as! DayHoursCell
        let index = indexPath.row
        cell.configure(draft.days[index])
        cell.onChange = { [weak self] day in
            guard let self = self else { return }
            let wasClosed = self.draft.days[index].isClosed
            self.draft.days[index] = day
            // Showing or hiding the time pickers changes the row height
            if wasClosed != day.isClosed {
                self.tableView.performBatchUpdates(nil)
            }
        }
        return cell
    }
}

// MARK: - Day cell

private final class DayHoursCell: UITableViewCell {
    static let reuseId = "DayHoursCell"

    var onChange: ((VenueHoursDraft.Day) -> Void)?
    private var day: VenueHoursDraft.Day?

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        return label
    }()
    private let stateLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        return label
    }()
    private let openSwitch = UISwitch()
    private let openPicker = DayHoursCell.timePicker()
    private let closePicker = DayHoursCell.timePicker()
    private let timesRow = UIStackView()

    private static func timePicker() -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval = 5
        return picker
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        openSwitch.onTintColor = Constants.Colors.primary
        openSwitch.addTarget(self, action: #selector(changed), for: .valueChanged)
        openPicker.addTarget(self, action: #selector(changed), for: .valueChanged)
        closePicker.addTarget(self, action: #selector(changed), for: .valueChanged)

        let nameStack = UIStackView(arrangedSubviews: [nameLabel, stateLabel])
        nameStack.axis = .vertical
        nameStack.spacing = 2
        let topRow = UIStackView(arrangedSubviews: [nameStack, openSwitch])
        topRow.alignment = .center

        let dash = UILabel()
        dash.text = "to"
        dash.textColor = Constants.Colors.secondaryLabel
        [openPicker, dash, closePicker, UIView()].forEach { timesRow.addArrangedSubview($0) }
        timesRow.spacing = 8
        timesRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [topRow, timesRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ day: VenueHoursDraft.Day) {
        self.day = day
        nameLabel.text = VenueHoursDraft.dayName(day.day)
        openSwitch.isOn = !day.isClosed
        openPicker.date = VenueHoursDraft.date(from: day.open)
        closePicker.date = VenueHoursDraft.date(from: day.close)
        render()
    }

    private func render() {
        let isOpen = openSwitch.isOn
        stateLabel.text = isOpen ? "Open" : "Closed"
        timesRow.isHidden = !isOpen
        openSwitch.accessibilityLabel = "\(nameLabel.text ?? "") open"
    }

    @objc private func changed() {
        guard var day = day else { return }
        day.isClosed = !openSwitch.isOn
        day.open = VenueHoursDraft.hhmm(from: openPicker.date)
        day.close = VenueHoursDraft.hhmm(from: closePicker.date)
        self.day = day
        render()
        onChange?(day)
    }
}
