import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore

/// Full-screen page for one widget, pushed from the Widgets tab. Thin
/// UIKit shell around the package's SwiftUI full view.
final class HomeWidgetDetailViewController: BaseViewController {
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareTapped)
        )

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

    @objc private func shareTapped(_ sender: UIBarButtonItem) {
        let descriptor = widget.descriptor
        guard let url = WidgetShareLink.url(widgetId: descriptor.id) else { return }
        AnalyticsService.shared.logEvent("widget_shared", parameters: ["widget_id": descriptor.id])
        let share = UIActivityViewController(
            activityItems: [WidgetShareLink.message(title: descriptor.title, subtitle: descriptor.subtitle), url],
            applicationActivities: nil
        )
        // An unanchored activity sheet is a crash on iPad, which is the device
        // App Review uses.
        share.popoverPresentationController?.barButtonItem = sender
        present(share, animated: true)
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
