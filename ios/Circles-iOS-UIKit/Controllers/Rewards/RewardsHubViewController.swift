import UIKit

/// The '$' section: two parallel money-ish systems under one roof.
///   Rewards      — store loyalty (points, offers, vouchers). Unchanged.
///   My Piggy Bank — FavCoins earned for contributing to FavCircles.
/// A segmented control swaps the two child controllers; each keeps its own
/// lifecycle and data. Deliberately a thin container — the systems must not
/// bleed into each other.
final class RewardsHubViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }

    // Piggy Bank leads: the $ button reads as "my money", and the piggy bank
    // always has something personal to show; store offers are situational.
    enum Tab: Int { case piggyBank = 0, rewards = 1 }

    private let rewardsVC = RewardsViewController()
    private let piggyBankVC = PiggyBankViewController()
    private var currentChild: UIViewController?

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Piggy Bank", "Store Points"])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Deep-link straight to a tab (e.g. the deposit toast could open the bank).
    var initialTab: Tab = .piggyBank

    /// When set (via the "your FavCoins are real crypto" engagement tip), the
    /// Piggy Bank child shows a one-off coach-mark pointing at the wallet
    /// create/link button once it's on screen.
    var showWalletCoachMarkOnAppear = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Rewards"

        // The hub is exactly where two-currencies confusion starts — one tap
        // to the FavCoins-vs-Store-Points explainer
        let differenceButton = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            style: .plain, target: self, action: #selector(differenceTapped))
        differenceButton.accessibilityLabel = "FavCoins vs Store Points"
        navigationItem.rightBarButtonItem = differenceButton
        view.backgroundColor = Constants.Colors.background

        view.addSubview(segmentedControl)
        view.addSubview(containerView)
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            containerView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Hand the coach-mark request to the child BEFORE it appears, so it can
        // fire on its own viewDidAppear once the wallet button is laid out.
        if showWalletCoachMarkOnAppear {
            piggyBankVC.pendingWalletCoachMark = true
        }

        segmentedControl.selectedSegmentIndex = initialTab.rawValue
        showTab(initialTab)
    }

    @objc private func tabChanged() {
        showTab(Tab(rawValue: segmentedControl.selectedSegmentIndex) ?? .piggyBank)
    }

    private func showTab(_ tab: Tab) {
        let next: UIViewController = (tab == .rewards) ? rewardsVC : piggyBankVC
        guard next !== currentChild else { return }

        if let current = currentChild {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        addChild(next)
        containerView.addSubview(next.view)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            next.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            next.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            next.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        next.didMove(toParent: self)
        currentChild = next

        // Title complements the segment instead of duplicating it.
        title = (tab == .rewards) ? "Store Points" : "FavCoins"
    }
}

extension RewardsHubViewController {
    @objc func differenceTapped() {
        guard let topic = HelpContentProvider.shared.topic(withId: "favcoin-vs-store-points") else { return }
        navigationController?.pushViewController(HelpTopicViewController(topic: topic), animated: true)
    }
}
