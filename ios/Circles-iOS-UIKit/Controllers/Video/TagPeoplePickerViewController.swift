import UIKit

/// Multi-select "Tag people" picker for a Moment upload — accepted
/// connections only (the backend re-validates; tagging is consent-scoped to
/// people who already accepted you). Returns denormalized TaggedMomentUser
/// values so the caller can show names immediately.
class TagPeoplePickerViewController: BaseViewController {

    static let maxTags = 10

    var initialSelection: [TaggedMomentUser] = []
    var onDone: (([TaggedMomentUser]) -> Void)?

    private var people: [User] = []
    private var selectedIds: Set<String> = []

    override var showsLoadingIndicator: Bool { true }
    override var emptyStateMessage: String? { "Connect with people to tag them in your Moments" }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tag People"
        view.backgroundColor = Constants.Colors.background
        selectedIds = Set(initialSelection.map { $0.id })

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                           target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done,
                                                            target: self, action: #selector(doneTapped))

        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func loadData(completion: (() -> Void)? = nil) {
        NetworkManager.shared.fetchConnections { [weak self] connections, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.people = (connections ?? [])
                    .filter { $0.status == .accepted }
                    .compactMap { $0.connectedUser }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                self.tableView.reloadData()
                completion?()
            }
        }
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func doneTapped() {
        let chosen = people
            .filter { selectedIds.contains($0.id) }
            .map { TaggedMomentUser(id: $0.id, displayName: $0.displayName, profilePicture: $0.profilePicture) }
        onDone?(chosen)
        dismiss(animated: true)
    }
}

extension TagPeoplePickerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { people.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "person")
            ?? UITableViewCell(style: .default, reuseIdentifier: "person")
        let person = people[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = person.displayName
        content.image = UIImage(systemName: "person.crop.circle.fill")
        content.imageProperties.maximumSize = CGSize(width: 34, height: 34)
        content.imageProperties.tintColor = Constants.Colors.primary.withAlphaComponent(0.4)
        cell.contentConfiguration = content
        cell.accessoryType = selectedIds.contains(person.id) ? .checkmark : .none
        cell.tintColor = Constants.Colors.primary
        if let urlString = person.profilePicture {
            ImageService.shared.loadImage(from: urlString) { [weak tableView] image in
                guard let image = image,
                      let cell = tableView?.cellForRow(at: indexPath) else { return }
                var updated = cell.defaultContentConfiguration()
                updated.text = person.displayName
                updated.image = image.rounded(to: CGSize(width: 34, height: 34))
                updated.imageProperties.maximumSize = CGSize(width: 34, height: 34)
                cell.contentConfiguration = updated
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let id = people[indexPath.row].id
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            guard selectedIds.count < Self.maxTags else {
                showError("You can tag up to \(Self.maxTags) people")
                return
            }
            selectedIds.insert(id)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}

private extension UIImage {
    /// Small circular avatar for table rows.
    func rounded(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
