import UIKit

/// A place-count achievement tier. Users earn badges as their saved-place
/// count grows; the current badge shows next to their name on their profile.
struct PlaceMilestone: Equatable {
    let threshold: Int
    let name: String
    let iconName: String
    let color: UIColor
}

enum PlaceMilestones {

    /// Ascending tiers. The profile badge always reflects the highest tier at
    /// or below the user's current place count; celebrations fire once per tier.
    static let all: [PlaceMilestone] = [
        PlaceMilestone(threshold: 5, name: "Explorer", iconName: "mappin.circle.fill", color: .systemTeal),
        PlaceMilestone(threshold: 10, name: "Adventurer", iconName: "map.fill", color: .systemGreen),
        PlaceMilestone(threshold: 20, name: "Pathfinder", iconName: "signpost.right.fill", color: .systemBlue),
        PlaceMilestone(threshold: 50, name: "Trailblazer", iconName: "flame.fill", color: .systemOrange),
        PlaceMilestone(threshold: 100, name: "Globetrotter", iconName: "globe.americas.fill", color: .systemIndigo),
        PlaceMilestone(threshold: 200, name: "Voyager", iconName: "airplane", color: .systemPurple),
        PlaceMilestone(threshold: 500, name: "Legend", iconName: "star.circle.fill", color: .systemPink),
        PlaceMilestone(threshold: 1000, name: "Cartographer", iconName: "crown.fill", color: .systemYellow)
    ]

    /// The badge earned at `count` places (nil below the first tier)
    static func badge(for count: Int) -> PlaceMilestone? {
        return all.last { count >= $0.threshold }
    }

    /// Per-account so switching users on one device doesn't suppress (or
    /// replay) another account's celebrations
    private static var celebratedKey: String {
        "highestCelebratedPlaceMilestone_\(AuthService.shared.getUserId() ?? "anonymous")"
    }

    /// Presents a one-time celebration when `totalPlaces` reaches a tier the
    /// user hasn't been congratulated for yet. Bulk jumps (e.g. imports)
    /// celebrate only the highest newly reached tier.
    static func celebrateIfNeeded(totalPlaces: Int?) {
        guard let totalPlaces = totalPlaces,
              let reached = badge(for: totalPlaces) else { return }
        let key = celebratedKey
        let celebrated = UserDefaults.standard.integer(forKey: key)
        guard reached.threshold > celebrated else { return }
        UserDefaults.standard.set(reached.threshold, forKey: key)

        // Give the add-place flow a beat to finish dismissing its own UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let presenter = topViewController() else { return }
            let celebrationVC = MilestoneCelebrationViewController(milestone: reached)
            celebrationVC.modalPresentationStyle = .overFullScreen
            celebrationVC.modalTransitionStyle = .crossDissolve
            presenter.present(celebrationVC, animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// A small explainer sheet reached by tapping the "i" on a profile badge —
/// the place-level tiers, or what Premium includes. Reusable for both.
final class BadgeInfoViewController: UIViewController {

    struct Row {
        let iconName: String
        let iconColor: UIColor
        let title: String
        let subtitle: String
        let isCurrent: Bool
        init(iconName: String, iconColor: UIColor, title: String,
             subtitle: String, isCurrent: Bool = false) {
            self.iconName = iconName
            self.iconColor = iconColor
            self.title = title
            self.subtitle = subtitle
            self.isCurrent = isCurrent
        }
    }

    private let titleText: String
    private let subtitleText: String
    private let rows: [Row]

    init(title: String, subtitle: String, rows: [Row]) {
        self.titleText = title
        self.subtitleText = subtitle
        self.rows = rows
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *), let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = titleText
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitleText
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 4

        let rowsStack = UIStackView(arrangedSubviews: rows.map(makeRowView))
        rowsStack.axis = .vertical
        rowsStack.spacing = 8

        let contentStack = UIStackView(arrangedSubviews: [headerStack, rowsStack])
        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(contentStack)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func makeRowView(_ row: Row) -> UIView {
        let container = UIView()
        if row.isCurrent {
            container.backgroundColor = row.iconColor.withAlphaComponent(0.12)
            container.layer.cornerRadius = 10
        }

        let icon = UIImageView(image: UIImage(systemName: row.iconName))
        icon.tintColor = row.iconColor
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = row.isCurrent ? "\(row.title)  •  You're here" : row.title
        title.font = .systemFont(ofSize: 15, weight: row.isCurrent ? .bold : .semibold)
        title.textColor = .label
        title.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = row.subtitle
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [title, subtitle])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(textStack)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),

            textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            textStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        return container
    }
}
