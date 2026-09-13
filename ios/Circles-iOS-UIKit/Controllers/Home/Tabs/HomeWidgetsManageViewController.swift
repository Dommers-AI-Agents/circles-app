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

    @objc private func doneTapped() {
        AnalyticsService.shared.logEvent("widget_manage_saved", parameters: ["enabled_count": model.visible.count])
        let model = self.model
        Task { await model.flushAll() }
        dismiss(animated: true)
    }
}
