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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The swipe-back gesture would bypass the widget's Back handling.
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        // Save anything pending as the user leaves.
        let model = self.model
        Task { await model.flushAll() }
    }

    @objc private func backTapped() {
        if let handle = context.handleBack, handle() { return }
        navigationController?.popViewController(animated: true)
    }
}
