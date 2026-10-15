import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore

/// Full-screen page for one widget, pushed from the Widgets tab. Thin
/// UIKit shell around the package's SwiftUI full view.
final class HomeWidgetDetailViewController: BaseViewController {
    /// Which widget this page shows, so a caller can tell whether it is
    /// already on screen before navigating to it.
    var widgetId: String { widget.descriptor.id }

    private let widget: any FavWidget
    private let context: WidgetContext
    private let model: WidgetsTabModel

    override var loadsDataOnViewDidLoad: Bool { false }
    override var reloadsDataOnAppear: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    init(widget: any FavWidget, context: WidgetContext, model: WidgetsTabModel) {
        self.widget = widget
        self.context = context
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = widget.descriptor.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationItem.largeTitleDisplayMode = .never
        // The widget can claim Back for itself (a live workout returning to
        // the widget's home page). A custom item is the only way to be asked.
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
        // Every widget gets this, including ones that don't exist yet: the
        // button lives on the shell all full views are pushed into, not in
        // any widget's own code.
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped)),
            pinButton,
            infoButton
        ]
        refreshPinButton()

        let hosting = UIHostingController(rootView: widget.makeFullView(context: context))
        hosting.view.backgroundColor = Constants.Colors.background
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    // MARK: - Pin to the Home button

    /// Adds this widget to both long-press menus: the app icon's (the list
    /// Settings → Home Screen Shortcuts edits) and the Home tab's.
    private lazy var pinButton = UIBarButtonItem(image: nil, style: .plain, target: self, action: #selector(pinTapped))

    /// What this widget is and what it does
    private lazy var infoButton: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain,
                                   target: self, action: #selector(pinInfoTapped))
        item.accessibilityLabel = "About \(widget.descriptor.title)"
        return item
    }()

    @objc private func pinInfoTapped() {
        let descriptor = widget.descriptor
        let about = WidgetAboutCatalog.about(id: descriptor.id, in: WidgetAboutCatalog.bundled,
                                             fallbackName: descriptor.title, fallbackTagline: descriptor.subtitle,
                                             fallbackDetail: descriptor.shareText)
        let aboutVC = WidgetAboutViewController(about: about, symbolName: descriptor.symbolName,
                                                accent: UIColor(hex: descriptor.accentHex))
        let nav = UINavigationController(rootViewController: aboutVC)
        nav.sheetPresentationController?.detents = [.medium(), .large()]
        nav.sheetPresentationController?.prefersGrabberVisible = true
        AnalyticsService.shared.logEvent("widget_about_opened", parameters: ["widget_id": descriptor.id])
        present(nav, animated: true)
    }

    private var thisPin: HomeButtonPin { HomeButtonPin(id: widget.descriptor.id, title: widget.descriptor.title) }

    private var storedShortcuts: [String]? {
        UserDefaults.standard.stringArray(forKey: HomeShortcutCatalog.selectionKey)
    }

    private var isPinned: Bool {
        (storedShortcuts ?? HomeShortcutCatalog.defaultSelection).contains(HomeShortcutCatalog.optionId(forWidget: thisPin.id))
            || HomeButtonPins.isPinned(thisPin.id, in: HomeButtonPinStore.load())
    }

    private func refreshPinButton() {
        let pinned = isPinned
        pinButton.image = UIImage(systemName: pinned ? "pin.fill" : "pin")
        pinButton.accessibilityLabel = pinned ? "Unpin from Home Screen shortcuts" : "Pin to Home Screen shortcuts"
    }

    @objc private func pinTapped() {
        let optionId = HomeShortcutCatalog.optionId(forWidget: thisPin.id)
        if isPinned {
            let stored = storedShortcuts ?? HomeShortcutCatalog.defaultSelection
            saveShortcuts(stored.filter { $0 != optionId }, homeTabPinned: false)
            announce(pinned: false)
            return
        }
        let result = HomeShortcutCatalog.pinToggled(widgetId: thisPin.id, stored: storedShortcuts)
        guard result.outcome == .full else {
            saveShortcuts(result.selection, homeTabPinned: true)
            announce(pinned: true, explain: true)
            return
        }
        // All four taken: show them and let the user pick which one goes
        let current = HomeShortcutCatalog.selection(stored: result.selection, options: shortcutOptions)
        HomeShortcutPrompts.askToSwap(adding: thisPin.title, current: current, from: self) { [weak self] removedId in
            guard let self else { return }
            self.saveShortcuts(HomeShortcutCatalog.replacing(removedId, with: optionId, in: result.selection), homeTabPinned: true)
            AnalyticsService.shared.logEvent("home_shortcut_swapped", parameters: ["added": optionId, "removed": removedId])
            self.announce(pinned: true)
        }
    }

    private var shortcutOptions: [HomeShortcutOption] {
        HomeShortcutCatalog.options(widgets: FavWidgetRegistry.descriptors.map {
            HomeShortcutCatalog.Widget(id: $0.id, title: $0.title, symbolName: $0.symbolName)
        })
    }

    /// The app-icon menu and the Home tab menu move together.
    private func saveShortcuts(_ selection: [String], homeTabPinned: Bool) {
        UserDefaults.standard.set(selection, forKey: HomeShortcutCatalog.selectionKey)
        let pins = HomeButtonPinStore.load().filter { $0.id != thisPin.id }
        HomeButtonPinStore.save(homeTabPinned ? HomeButtonPins.toggle(thisPin, in: pins) : pins)
        QuickCheckInShortcuts.updateFromCache()
        refreshPinButton()
    }

    private func announce(pinned: Bool, explain: Bool = false) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AnalyticsService.shared.logEvent(pinned ? "widget_pinned_home_button" : "widget_unpinned_home_button",
                                         parameters: ["widget_id": thisPin.id])
        if explain {
            HomeShortcutPrompts.showPinned(title: thisPin.title, from: self)
            return
        }
        AlertPresenter.showBriefMessage(
            pinned ? "Pinned. Press and hold the FavCircles icon (or the Home tab) to jump to \(thisPin.title)."
                   : "Unpinned.",
            from: self, duration: pinned ? 2.4 : 1.2)
    }

    /// Every widget's share card (WidgetShareKit): the widget's own card when
    /// it has one (FavRun: the latest route), otherwise the generic card —
    /// one tappable bubble that opens this widget (Wes, 2026-10-09).
    @objc private func shareTapped(_ sender: UIBarButtonItem) {
        let descriptor = widget.descriptor
        AnalyticsService.shared.logEvent("widget_shared", parameters: ["widget_id": descriptor.id])
        sender.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            let items = await WidgetShareKit.items(for: self.widget, context: self.context)
            sender.isEnabled = true
            let activityItems = items.compactMap(\.activityItem)
            let share = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            // An unanchored activity sheet is a crash on iPad, which is the device
            // App Review uses.
            share.popoverPresentationController?.barButtonItem = sender
            self.present(share, animated: true)
        }
    }

    private weak var previousPopDelegate: UIGestureRecognizerDelegate?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Swipe-back stays on for every widget page; it only yields while a
        // widget has claimed Back for itself (a live workout).
        if let gesture = navigationController?.interactivePopGestureRecognizer, gesture.delegate !== self {
            previousPopDelegate = gesture.delegate
            gesture.delegate = self
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let gesture = navigationController?.interactivePopGestureRecognizer, gesture.delegate === self {
            gesture.delegate = previousPopDelegate
        }
        // Save anything pending as the user leaves.
        let model = self.model
        Task { await model.flushAll() }
    }

    @objc private func backTapped() {
        if let handle = context.handleBack, handle() { return }
        navigationController?.popViewController(animated: true)
    }
}

extension HomeWidgetDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // A swipe would bypass the widget's own Back handling.
        context.handleBack == nil && (navigationController?.viewControllers.count ?? 0) > 1
    }
}
