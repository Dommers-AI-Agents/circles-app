import UIKit
import SwiftUI
import FavWidgets

/// "Manage" sheet for the Widgets tab: reorder and enable/disable widgets.
final class HomeWidgetsManageViewController: BaseViewController {
    private let model: WidgetsTabModel

    override var loadsDataOnViewDidLoad: Bool { false }
    override var reloadsDataOnAppear: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    init(model: WidgetsTabModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = "Manage Widgets"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        navigationItem.leftBarButtonItem = pinButton
        refreshPinButton()

        let hosting = UIHostingController(rootView: WidgetManageView(model: model))
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    // MARK: Pin the Widgets tab to the app icon (Wes, 2026-11-20)

    /// Same list Settings → Data edits and the widget pages' pin button
    /// uses; this row is the tab itself, option id "widgets".
    private let widgetsOptionId = "widgets"

    private lazy var pinButton = UIBarButtonItem(image: UIImage(systemName: "pin"), style: .plain,
                                                 target: self, action: #selector(pinTapped))

    private var storedShortcuts: [String]? { HomeShortcutSettings.storedSelection }

    private var isPinned: Bool {
        (storedShortcuts ?? HomeShortcutCatalog.defaultSelection).contains(widgetsOptionId)
    }

    private func refreshPinButton() {
        pinButton.image = UIImage(systemName: isPinned ? "pin.fill" : "pin")
        pinButton.accessibilityLabel = isPinned ? "Unpin Widgets from the app icon menu" : "Pin Widgets to the app icon menu"
    }

    @objc private func pinTapped() {
        let result = HomeShortcutCatalog.pinToggled(optionId: widgetsOptionId, stored: storedShortcuts)
        switch result.outcome {
        case .removed:
            save(result.selection)
            AlertPresenter.showBriefMessage("Unpinned.", from: self)
        case .added:
            save(result.selection)
            AlertPresenter.showBriefMessage("Pinned. Press and hold the FavCircles icon to jump straight to Widgets.", from: self)
        case .full:
            // All four taken: show them and let the user pick which one goes
            let current = HomeShortcutCatalog.selection(stored: result.selection, options: shortcutOptions)
            HomeShortcutPrompts.askToSwap(adding: "Widgets", current: current, from: self) { [weak self] removedId in
                guard let self else { return }
                self.save(HomeShortcutCatalog.replacing(removedId, with: self.widgetsOptionId, in: result.selection))
                AnalyticsService.shared.logEvent("home_shortcut_swapped", parameters: ["added": self.widgetsOptionId, "removed": removedId])
                AlertPresenter.showBriefMessage("Pinned. Press and hold the FavCircles icon to jump straight to Widgets.", from: self)
            }
        }
    }

    private var shortcutOptions: [HomeShortcutOption] {
        HomeShortcutCatalog.options(widgets: FavWidgetRegistry.descriptors.map {
            HomeShortcutCatalog.Widget(id: $0.id, title: $0.title, symbolName: $0.symbolName)
        })
    }

    private func save(_ selection: [String]) {
        HomeShortcutSettings.saveSelection(selection)
        QuickCheckInShortcuts.updateFromCache()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AnalyticsService.shared.logEvent(isPinned ? "widgets_tab_pinned_app_icon" : "widgets_tab_unpinned_app_icon")
        refreshPinButton()
    }

    @objc private func doneTapped() {
        AnalyticsService.shared.logEvent("widget_manage_saved", parameters: ["enabled_count": model.visible.count])
        let model = self.model
        Task { await model.flushAll() }
        dismiss(animated: true)
    }
}
