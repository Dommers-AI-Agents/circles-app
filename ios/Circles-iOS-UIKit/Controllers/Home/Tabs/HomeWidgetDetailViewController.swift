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
            pinButton
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

    /// Adds this widget to the Home button's long-press menu
    private lazy var pinButton = UIBarButtonItem(image: nil, style: .plain, target: self, action: #selector(pinTapped))

    private var thisPin: HomeButtonPin { HomeButtonPin(id: widget.descriptor.id, title: widget.descriptor.title) }

    private func refreshPinButton() {
        let pinned = HomeButtonPins.isPinned(thisPin.id, in: HomeButtonPinStore.load())
        pinButton.image = UIImage(systemName: pinned ? "pin.fill" : "pin")
        pinButton.accessibilityLabel = pinned ? "Unpin from Home button" : "Pin to Home button"
    }

    @objc private func pinTapped() {
        let before = HomeButtonPinStore.load()
        let after = HomeButtonPins.toggle(thisPin, in: before)
        HomeButtonPinStore.save(after)
        refreshPinButton()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let pinned = HomeButtonPins.isPinned(thisPin.id, in: after)
        AnalyticsService.shared.logEvent(pinned ? "widget_pinned_home_button" : "widget_unpinned_home_button",
                                         parameters: ["widget_id": thisPin.id])
        AlertPresenter.showBriefMessage(
            pinned ? "Pinned. Press and hold Home to jump to \(thisPin.title) from anywhere."
                   : "Unpinned from the Home button.",
            from: self, duration: pinned ? 2.2 : 1.2)
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
            let activityItems: [Any] = items.compactMap { item in
                switch item {
                case .text(let text): return text
                case .url(let url): return url
                case .imageJPEG(let data): return UIImage(data: data)
                case .link(let url, let title, let jpeg): return LinkPreviewItem(url: url, title: title, image: jpeg.flatMap(UIImage.init(data:)))
                }
            }
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
