import UIKit

/// A store's full menu as customers see it (2026-10-20): its sections with
/// a chip row to jump between them, every item with its price as printed,
/// and a search box ("vegan", "pizza", "$10"). Read-only; the owner edits
/// it in VenueMenuEditorViewController.
final class PlaceMenuViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    private let menu: StorefrontMenu
    private let label: String
    private let placeName: String
    private var shown: [StorefrontMenuSection]

    private let searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.autocapitalizationType = .none
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private let chips: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    private let chipScroll: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64
        table.allowsSelection = false
        table.keyboardDismissMode = .onDrag
        return table
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(menu: StorefrontMenu, label: String, placeName: String) {
        self.menu = menu
        self.label = label
        self.placeName = placeName
        self.shown = menu.sections
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\(placeName) \u{00B7} \(label)"
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        searchBar.placeholder = "Search the \(label.lowercased())"
        searchBar.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "item")
        chipScroll.addSubview(chips)
        [searchBar, chipScroll, tableView, emptyLabel].forEach(view.addSubview)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            chipScroll.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            chipScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chipScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chipScroll.heightAnchor.constraint(equalToConstant: 44),
            chips.topAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.topAnchor, constant: 4),
            chips.bottomAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.bottomAnchor, constant: -4),
            chips.leadingAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.leadingAnchor, constant: 16),
            chips.trailingAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.trailingAnchor, constant: -16),
            chips.heightAnchor.constraint(equalTo: chipScroll.frameLayoutGuide.heightAnchor, constant: -8),
            tableView.topAnchor.constraint(equalTo: chipScroll.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.topAnchor.constraint(equalTo: chipScroll.bottomAnchor, constant: 40),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
        buildChips()
        AnalyticsService.shared.logEvent("place_menu_opened", parameters: ["items": String(menu.itemCount)])
    }

    private func buildChips() {
        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chipScroll.isHidden = shown.count < 2
        for (index, section) in shown.enumerated() {
            let chip = UIButton.pillButton(title: section.name)
            chip.addAction(UIAction { [weak self] _ in
                guard let self, self.tableView.numberOfRows(inSection: index) > 0 else { return }
                self.tableView.scrollToRow(at: IndexPath(row: 0, section: index), at: .top, animated: true)
            }, for: .touchUpInside)
            chips.addArrangedSubview(chip)
        }
    }

    /// Words in the item's name, description, tags or price, every word
    /// matching somewhere ("vegan pizza")
    static func filter(_ menu: StorefrontMenu, query: String) -> [StorefrontMenuSection] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return menu.sections }
        return menu.sections.compactMap { section in
            let sectionName = section.name.lowercased()
            let items = section.items.filter { item in
                let hay = ([item.name, item.description ?? "", item.price ?? "", sectionName] + item.tags).joined(separator: " ").lowercased()
                return words.allSatisfy { hay.contains($0) }
            }
            return items.isEmpty ? nil : StorefrontMenuSection(id: section.id, name: section.name, items: items)
        }
    }
}

extension PlaceMenuViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        shown = Self.filter(menu, query: searchText)
        emptyLabel.text = "Nothing on the \(label.lowercased()) matches \u{201C}\(searchText)\u{201D}."
        emptyLabel.isHidden = !shown.isEmpty
        buildChips()
        tableView.reloadData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
}

extension PlaceMenuViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { shown.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shown[section].items.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { shown[section].name }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath)
        let item = shown[indexPath.section].items[indexPath.row]
        var config = UIListContentConfiguration.subtitleCell()
        config.text = item.name
        config.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
        let details = [item.description, item.tags.isEmpty ? nil : item.tags.joined(separator: " · ")].compactMap { $0 }
        config.secondaryText = details.isEmpty ? nil : details.joined(separator: "\n")
        config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
        config.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = config
        if let price = item.price {
            let priceLabel = UILabel()
            priceLabel.text = price
            priceLabel.font = .systemFont(ofSize: 16, weight: .semibold)
            priceLabel.textColor = Constants.Colors.label
            priceLabel.sizeToFit()
            cell.accessoryView = priceLabel
        } else {
            cell.accessoryView = nil
        }
        return cell
    }
}
