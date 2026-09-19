import UIKit
import FavWidgets

/// Settings → Home Screen Shortcuts: pick up to four quick actions for the
/// app icon's long-press menu. Free slots become "Check in at <nearby place>".
final class HomeShortcutsViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let options: [HomeShortcutOption]
    private var selection: [String]

    init() {
        let widgets = FavWidgetRegistry.descriptors.map {
            HomeShortcutCatalog.Widget(id: $0.id, title: $0.title, symbolName: $0.symbolName)
        }
        options = HomeShortcutCatalog.options(widgets: widgets)
        selection = HomeShortcutCatalog.selection(
            stored: UserDefaults.standard.stringArray(forKey: HomeShortcutCatalog.selectionKey),
            options: options
        ).map(\.id)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home Screen Shortcuts"
        view.backgroundColor = Constants.Colors.background
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "option")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func save() {
        UserDefaults.standard.set(selection, forKey: HomeShortcutCatalog.selectionKey)
        QuickCheckInShortcuts.updateFromCache()
    }

    private var footerText: String {
        let free = HomeShortcutCatalog.nearbySlots(selectedCount: selection.count)
        let chosen = "\(selection.count) of \(HomeShortcutCatalog.maxSelected) chosen."
        switch free {
        case 0: return "\(chosen) Long-press the Circles icon on your Home Screen to use them."
        case 1: return "\(chosen) The last slot shows \"Check in at\" your nearest saved place."
        default: return "\(chosen) The \(free) free slots show \"Check in at\" your nearest saved places."
        }
    }
}

extension HomeShortcutsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { options.count }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { footerText }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "option", for: indexPath)
        let option = options[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = option.title
        config.secondaryText = option.subtitle
        config.secondaryTextProperties.color = .secondaryLabel
        config.image = UIImage(systemName: option.symbolName)
        config.imageProperties.tintColor = Constants.Colors.primary
        cell.contentConfiguration = config
        let position = selection.firstIndex(of: option.id)
        cell.accessoryType = position != nil ? .checkmark : .none
        cell.tintColor = Constants.Colors.primary
        let full = selection.count >= HomeShortcutCatalog.maxSelected && position == nil
        cell.contentConfiguration = config
        cell.selectionStyle = .default
        cell.alpha = full ? 0.45 : 1
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let option = options[indexPath.row]
        let next = HomeShortcutCatalog.toggled(option.id, in: selection)
        if next == selection {
            showError("You can choose up to \(HomeShortcutCatalog.maxSelected). Uncheck one first.")
            return
        }
        selection = next
        save()
        tableView.reloadData()
    }
}
