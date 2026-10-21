import UIKit

/// A store's full menu as customers see it (2026-10-20): its sections with
/// a chip row to jump between them, every item with its price as printed,
/// and a search box ("vegan", "pizza", "$10"). The owner edits it in
/// VenueMenuEditorViewController. When the store takes orders (Business,
/// pay at pickup), each item has Add and the bottom bar opens the order.
final class PlaceMenuViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    private let menu: StorefrontMenu
    private let label: String
    private let placeName: String
    private var shown: [StorefrontMenuSection]
    /// Set when the store takes orders in the app
    private let ordering: StoreOrdering?
    private let venueId: String?
    /// The owner trying it as a customer: orders go in marked TEST
    private let testOrder: Bool
    private var cart = OrderCart()
    private lazy var orderBar = UIButton.primaryButton(title: "View order")

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

    init(menu: StorefrontMenu, label: String, placeName: String, ordering: StoreOrdering? = nil, venueId: String? = nil,
         testOrder: Bool = false) {
        self.testOrder = testOrder
        self.menu = menu
        self.label = label
        self.placeName = placeName
        self.shown = menu.sections
        self.ordering = ordering
        self.venueId = venueId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = testOrder ? "Try it as a customer" : "\(placeName) \u{00B7} \(label)"
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
        if ordering != nil { installOrderBar() }
        AnalyticsService.shared.logEvent("place_menu_opened", parameters: ["items": String(menu.itemCount), "ordering": ordering == nil ? "no" : "yes"])
    }

    // MARK: - Ordering

    private func installOrderBar() {
        orderBar.translatesAutoresizingMaskIntoConstraints = false
        orderBar.addTarget(self, action: #selector(orderBarTapped), for: .touchUpInside)
        view.addSubview(orderBar)
        NSLayoutConstraint.activate([
            orderBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            orderBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            orderBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
        tableView.contentInset.bottom = 80
        renderOrderBar()
    }

    private func renderOrderBar() {
        guard ordering != nil else { return }
        orderBar.isHidden = cart.isEmpty
        let est = cart.estimate
        let money = OrderCart.estimateText(total: est.total, partial: est.partial).map { " \u{00B7} \($0)" } ?? ""
        orderBar.setTitle("View order \u{00B7} \(cart.itemCount) item\(cart.itemCount == 1 ? "" : "s")\(money)", for: .normal)
    }

    private func add(_ item: StorefrontMenuItem) {
        cart.add(item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        renderOrderBar()
        tableView.reloadData()
    }

    @objc private func orderBarTapped() {
        guard let ordering, let venueId else { return }
        let review = OrderReviewViewController(venueId: venueId, placeName: placeName, ordering: ordering, cart: cart, testOrder: testOrder)
        review.onCartChanged = { [weak self] cart in
            self?.cart = cart
            self?.renderOrderBar()
            self?.tableView.reloadData()
        }
        navigationController?.pushViewController(review, animated: true)
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
        let priceLabel = UILabel()
        priceLabel.text = item.price
        priceLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        priceLabel.textColor = Constants.Colors.label
        if ordering != nil {
            // Price, then Add (or how many are in the order)
            let qty = cart.quantity(of: item.id)
            let add = UIButton.smallActionButton(title: qty > 0 ? "\(qty) \u{2713}" : "Add", style: qty > 0 ? .primary : .secondary)
            add.addAction(UIAction { [weak self] _ in self?.add(item) }, for: .touchUpInside)
            add.accessibilityLabel = qty > 0 ? "Add another \(item.name), \(qty) in your order" : "Add \(item.name) to your order"
            let row = UIStackView(arrangedSubviews: [priceLabel, add])
            row.spacing = 10
            row.alignment = .center
            row.frame.size = row.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            cell.accessoryView = row
        } else if item.price != nil {
            priceLabel.sizeToFit()
            cell.accessoryView = priceLabel
        } else {
            cell.accessoryView = nil
        }
        return cell
    }
}
