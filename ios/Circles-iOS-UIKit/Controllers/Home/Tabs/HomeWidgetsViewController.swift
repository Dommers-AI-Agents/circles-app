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

    /// Refetches one widget's data — a push about it just arrived, so what is
    /// on screen ("Waiting for Mom to accept") may be minutes stale.
    func refreshWidget(id widgetId: String) {
        guard let model, let descriptor = model.descriptors.first(where: { $0.id == widgetId }),
              let widget = model.widget(for: descriptor) else { return }
        let context = model.context(for: descriptor)
        Task { await widget.refresh(context: context) }
    }

    /// Opens one widget's full page by id (push taps, deep links). A postcard
    /// order id is handed to the page through its context, like a launch
    /// photo, so the page opens on that card's status.
    func open(widgetId: String, postcardOrderId: String? = nil, quoteId: String? = nil, workoutPostId: String? = nil,
              drinkId: String? = nil, motivationLineId: String? = nil, motivationSend: Bool = false,
              postcardShareToken: String? = nil, eventToken: String? = nil, eventId: String? = nil,
              runId: String? = nil, runToken: String? = nil, careAskId: String? = nil) {
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
        // A received card (its printed QR / the web page's Open button)
        if widgetId == "postcard", let postcardShareToken { context.launchPostcardShareToken = postcardShareToken }
        // An event invite link/push (join screen) or an event push (open it)
        if widgetId == "events", let eventToken { context.launchEventToken = eventToken }
        if widgetId == "events", let eventId { context.launchEventId = eventId }
        if widgetId == "quotes", let quoteId { context.launchQuoteId = quoteId }
        // FavRun: a run to watch (push / feed row) or a watch link to join
        if widgetId == "run", let runId { context.launchRunId = runId }
        if widgetId == "run", let runToken { context.launchRunToken = runToken }
        // How Are You?: an answer push opens that answer
        if widgetId == "howareyou", let careAskId { context.launchCareAskId = careAskId }
        // A shared workout tapped in the activity feed opens over the page
        if widgetId == "workouts", let workoutPostId { context.launchWorkoutPostId = workoutPostId }
        // A drink a friend sent, tapped in chat, opens on that recipe
        if widgetId == "drink", let drinkId { context.launchDrinkId = drinkId }
        // Coach Mane's line: from a push's "Send to someone" (send sheet up)
        // or a friend's chat card (just that line)
        if widgetId == "motivation", let motivationLineId {
            context.launchMotivationLineId = motivationLineId
            context.launchMotivationSend = motivationSend
        }
        Task { await widget.refresh(context: context) }
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
        // Same as arriving by link: a widget they had turned off comes back
        // on, so Back lands on a list that has the page they were just in.
        if !model.visible.contains(where: { $0.id == descriptor.id }) {
            model.setEnabled(true, id: descriptor.id)
        }
        let context = model.context(for: descriptor)
        context.launchPhoto = WidgetLaunchPhoto(image: photo, place: place)
        open(widget, context: context)
    }

    /// A shared workout from the activity feed, straight over the feed: no
    /// tab switch, no pushed Workouts page, no wait before the fetch starts
    /// (Wes, 2026-10-07: it was slow). Start → the Workouts page with the
    /// live workout.
    func presentWorkoutPost(postId: String, title: String?, detail: String?) {
        guard ensureModel(), let model,
              let descriptor = model.descriptors.first(where: { $0.id == "workouts" }),
              let workouts = model.widget(for: descriptor) as? WorkoutWidget else { return }
        let context = model.context(for: descriptor)
        let sheet = UIHostingController(rootView: workouts.makePostView(
            context: context, postId: postId, previewTitle: title, previewDetail: detail,
            onStarted: { [weak self] in self?.open(widgetId: "workouts") },
            onOpenWorkouts: { [weak self] in self?.open(widgetId: "workouts") }
        ))
        sheet.modalPresentationStyle = .pageSheet
        present(sheet, animated: true)
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
