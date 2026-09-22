import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore

/// The home screen's Widgets tab: daily-use mini-apps (water, habits,
/// calories, workouts, bill split, postcards) from the FavWidgets package.
/// UIKit owns the tab, navigation and sheets; the package's SwiftUI views
/// are hosted inside.
final class HomeWidgetsViewController: BaseViewController, HomeContentTab {
    weak var host: HomeContentTabHost?
    var isActiveTab = false

    private var widgetHost: AppWidgetHost?
    private var model: WidgetsTabModel?
    private var hostingController: UIHostingController<WidgetsTabRootView>?
    private let statusView = HomeTabStatusView()
    private var hintBubble: BubbleView?
    private var lifecycleObservers: [NSObjectProtocol] = []

    // The host's segment switch drives loading; nothing loads on its own.
    override var loadsDataOnViewDidLoad: Bool { false }
    override var reloadsDataOnAppear: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        observeLifecycle()
        view.addSubview(statusView)
        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: view.topAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Pending edits go out when the app leaves the screen (inside a short
    /// background task so the PUT can finish) and when the connection comes
    /// back — a save refused offline is kept on disk and retried here.
    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let model = self?.model else { return }
            var taskId = UIBackgroundTaskIdentifier.invalid
            taskId = UIApplication.shared.beginBackgroundTask(withName: "widgets.flush") {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = .invalid
            }
            Task {
                await model.flushAll()
                if taskId != .invalid { UIApplication.shared.endBackgroundTask(taskId) }
            }
        })
        lifecycleObservers.append(center.addObserver(forName: .networkReachabilityDidChange, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?[NetworkMonitor.isConnectedKey] as? Bool == true, let model = self?.model else { return }
            Task { await model.flushAll() }
        })
    }

    // MARK: - HomeContentTab

    func tabDidBecomeVisible() {
        guard ensureModel() else { return }
        AnalyticsService.shared.logEvent("widgets_tab_viewed")
        maybeShowHint()
    }

    func tabWillHide() {
        hintBubble?.dismiss { [weak self] in
            self?.hintBubble?.removeFromSuperview()
            self?.hintBubble = nil
        }
        guard let model else { return }
        Task { await model.flushAll() }
    }

    func refreshTab() {
        guard let model else {
            host?.endRefreshing()
            return
        }
        Task { [weak self] in
            await model.refreshAll()
            self?.host?.endRefreshing()
        }
    }

    // MARK: - Model

    /// Builds the package model for the signed-in user (rebuilding after an
    /// account switch). Returns false when nobody is signed in.
    @discardableResult
    private func ensureModel() -> Bool {
        guard let userId = KeychainService.shared.getUserId(), !userId.isEmpty else {
            statusView.message = "Sign in to use widgets"
            return false
        }
        if let widgetHost, widgetHost.userId == userId, model != nil { return true }

        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        let widgetHost = AppWidgetHost(userId: userId)
        widgetHost.presenter = self
        let model = WidgetsTabModel(host: widgetHost, theme: AppWidgetHost.makeTheme())
        model.onOpen = { [weak self] widget, context in self?.open(widget, context: context) }
        model.onManage = { [weak self] in self?.presentManage() }

        let hosting = UIHostingController(rootView: WidgetsTabRootView(model: model))
        hosting.view.backgroundColor = Constants.Colors.background
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(hosting.view, belowSubview: statusView)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)

        self.widgetHost = widgetHost
        self.model = model
        self.hostingController = hosting
        statusView.message = nil
        return true
    }

    // MARK: - Navigation

    /// Opens one widget's full page by id (push taps, deep links). A postcard
    /// order id is handed to the page through its context, like a launch
    /// photo, so the page opens on that card's status.
    func open(widgetId: String, postcardOrderId: String? = nil, quoteId: String? = nil) {
        guard ensureModel(), let model,
              let descriptor = model.descriptors.first(where: { $0.id == widgetId }),
              let widget = model.widget(for: descriptor) else { return }
        if navigationController?.topViewController is HomeWidgetDetailViewController {
            navigationController?.popViewController(animated: false)
        }
        // Arriving from a shared link for a widget they had turned off: turn
        // it on, so going Back shows the thing they were just sent rather than
        // a list it isn't in.
        if !model.visible.contains(where: { $0.id == widgetId }) {
            model.setEnabled(true, id: widgetId)
        }
        let context = model.context(for: descriptor)
        if widgetId == "postcard", let postcardOrderId { context.launchPostcardOrderId = postcardOrderId }
        if widgetId == "quotes", let quoteId { context.launchQuoteId = quoteId }
        open(widget, context: context)
    }

    /// Moments → postcard: open the postcard page with `photo` already chosen
    /// (and the moment's place as the caption place). The photo is handed to
    /// the widget through its context right before the page appears.
    func openPostcard(photo: UIImage, place: WidgetPlaceRef?) {
        guard ensureModel(), let model,
              let descriptor = model.descriptors.first(where: { $0.id == "postcard" }),
              let widget = model.widget(for: descriptor) else { return }
        if navigationController?.topViewController is HomeWidgetDetailViewController {
            navigationController?.popViewController(animated: false)
        }
        let context = model.context(for: descriptor)
        context.launchPhoto = WidgetLaunchPhoto(image: photo, place: place)
        open(widget, context: context)
    }

    private func open(_ widget: any FavWidget, context: WidgetContext) {
        guard let model else { return }
        let detail = HomeWidgetDetailViewController(widget: widget, context: context, model: model)
        context.closeFullView = { [weak detail] in
            detail?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(detail, animated: true)
    }

    private func presentManage() {
        guard let model else { return }
        let manage = HomeWidgetsManageViewController(model: model)
        let nav = UINavigationController(rootViewController: manage)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    // MARK: - First-use hint

    private func maybeShowHint() {
        guard OnboardingManager.shared.shouldShowHomeWidgetsHint(), hintBubble == nil,
              let target = hostingController?.view else { return }
        OnboardingManager.shared.markHomeWidgetsHintShown()
        let bubble = BubbleView()
        bubble.configureHint(
            title: "Your daily widgets",
            description: "Track water, habits, workouts and more — right here. Tap Manage to choose and reorder them.",
            arrowDirection: .top
        )
        bubble.onNext = { [weak self, weak bubble] in
            bubble?.dismiss { bubble?.removeFromSuperview() }
            self?.hintBubble = nil
        }
        view.addSubview(bubble)
        bubble.pointTo(target, in: view)
        bubble.show()
        hintBubble = bubble
    }
}
