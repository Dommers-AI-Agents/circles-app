import UIKit

/// Where a milestone push lands — "🥈 Second place! You added 14 places this
/// month", "🌟 10 places added!", a connections or moments milestone.
/// The celebration up top, then something real underneath: your month of
/// adding places (count, rank, how far behind first), a board of you and
/// your connections, the places you added, and what to do next.
final class MilestoneMonthViewController: BaseViewController {

    struct Month: Decodable {
        struct Row: Decodable {
            let userId: String
            let displayName: String
            let profilePicture: String?
            let count: Int
            let isMe: Bool
        }
        struct PlaceItem: Decodable {
            let id: String
            let name: String
            let photo: String?
        }
        let windowDays: Int
        let count: Int
        let rank: Int?
        let contributors: Int
        let behindFirst: Int?
        let board: [Row]
        let places: [PlaceItem]
    }
    private struct Envelope: Decodable { let success: Bool; let data: Month }

    private let milestone: PushMilestone
    private var month: Month?

    private let scroll = UIScrollView()
    private let stack = UIStackView()

    init(milestone: PushMilestone) {
        self.milestone = milestone
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = MilestoneCopy.navTitle(milestone)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeTapped))
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        view.sendSubviewToBack(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32)
        ])
        render()
    }

    override func loadData(completion: (() -> Void)? = nil) {
        APIService.shared.request(endpoint: "users/me/contributions", method: .get) { [weak self] (result: Result<Envelope, APIError>) in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                if case .success(let envelope) = result { self.month = envelope.data }
                self.render()
            }
        }
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    // MARK: - Layout

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(heroCard())

        if let month {
            stack.addArrangedSubview(statsRow(month))
            if month.board.count > 1 { stack.addArrangedSubview(boardSection(month)) }
            if !month.places.isEmpty { stack.addArrangedSubview(placesSection(month)) }
        }
        stack.addArrangedSubview(actions())
    }

    private func heroCard() -> UIView {
        let emoji = UILabel()
        emoji.text = MilestoneCopy.emoji(milestone)
        emoji.font = .systemFont(ofSize: 56)
        emoji.textAlignment = .center
        let title = UILabel()
        title.text = MilestoneCopy.headline(milestone, month: month.map { ($0.count, $0.rank) })
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textAlignment = .center
        title.numberOfLines = 0
        let detail = UILabel()
        detail.text = MilestoneCopy.detail(milestone, count: month?.count, behindFirst: month?.behindFirst)
        detail.font = .systemFont(ofSize: 15)
        detail.textColor = .secondaryLabel
        detail.textAlignment = .center
        detail.numberOfLines = 0
        let column = UIStackView(arrangedSubviews: [emoji, title, detail])
        column.axis = .vertical
        column.spacing = 6
        column.alignment = .fill
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)
        column.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.10)
        column.layer.cornerRadius = 16
        return column
    }

    private func statsRow(_ month: Month) -> UIView {
        let tiles = [
            tile("\(month.count)", "places in \(month.windowDays) days"),
            tile(month.rank.map { MilestoneCopy.ordinal($0) } ?? "—", "of \(month.contributors) adding places"),
            tile(month.behindFirst.map { $0 == 0 ? "1st" : "\($0)" } ?? "—", month.behindFirst == 0 ? "you're leading" : "behind first place")
        ]
        let row = UIStackView(arrangedSubviews: tiles)
        row.spacing = 10
        row.distribution = .fillEqually
        return row
    }

    private func tile(_ value: String, _ caption: String) -> UIView {
        let number = UILabel()
        number.text = value
        number.font = .systemFont(ofSize: 22, weight: .bold)
        number.textAlignment = .center
        let label = UILabel()
        label.text = caption
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        let column = UIStackView(arrangedSubviews: [number, label])
        column.axis = .vertical
        column.spacing = 2
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 6, bottom: 12, trailing: 6)
        column.backgroundColor = .secondarySystemBackground
        column.layer.cornerRadius = 12
        return column
    }

    private func boardSection(_ month: Month) -> UIView {
        let header = sectionHeader("You and your connections, last \(month.windowDays) days")
        let rows = month.board.enumerated().map { index, row -> UIView in
            let place = UILabel()
            place.text = "\(index + 1)"
            place.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
            place.textColor = .secondaryLabel
            place.widthAnchor.constraint(equalToConstant: 24).isActive = true
            let name = UILabel()
            name.text = row.isMe ? "\(row.displayName) (you)" : row.displayName
            name.font = .systemFont(ofSize: 16, weight: row.isMe ? .semibold : .regular)
            let count = UILabel()
            count.text = row.count == 1 ? "1 place" : "\(row.count) places"
            count.font = .systemFont(ofSize: 15)
            count.textColor = .secondaryLabel
            count.setContentHuggingPriority(.required, for: .horizontal)
            let line = UIStackView(arrangedSubviews: [place, name, count])
            line.spacing = 10
            line.isLayoutMarginsRelativeArrangement = true
            line.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
            line.backgroundColor = row.isMe ? Constants.Colors.primary.withAlphaComponent(0.08) : .clear
            line.layer.cornerRadius = 10
            return line
        }
        let list = UIStackView(arrangedSubviews: rows)
        list.axis = .vertical
        list.spacing = 2
        let column = UIStackView(arrangedSubviews: [header, list])
        column.axis = .vertical
        column.spacing = 8
        return column
    }

    private func placesSection(_ month: Month) -> UIView {
        let header = sectionHeader("What you added")
        let row = UIStackView()
        row.spacing = 10
        for item in month.places {
            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 104).isActive = true
            let thumb = UIImageView()
            thumb.contentMode = .scaleAspectFill
            thumb.clipsToBounds = true
            thumb.layer.cornerRadius = 10
            thumb.backgroundColor = .secondarySystemBackground
            thumb.image = UIImage(systemName: "mappin.circle")
            thumb.tintColor = .tertiaryLabel
            thumb.translatesAutoresizingMaskIntoConstraints = false
            thumb.heightAnchor.constraint(equalToConstant: 104).isActive = true
            if let photo = item.photo {
                ImageService.shared.loadImage(from: photo) { image in
                    DispatchQueue.main.async { if let image { thumb.image = image } }
                }
            }
            let name = UILabel()
            name.text = item.name
            name.font = .systemFont(ofSize: 12, weight: .medium)
            name.numberOfLines = 2
            let column = UIStackView(arrangedSubviews: [thumb, name])
            column.axis = .vertical
            column.spacing = 4
            column.isUserInteractionEnabled = false
            column.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(column)
            NSLayoutConstraint.activate([
                column.topAnchor.constraint(equalTo: button.topAnchor),
                column.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                column.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                column.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            button.accessibilityLabel = item.name
            button.addAction(UIAction { [weak self] _ in self?.open(ShareLinks.place(id: item.id, refUserId: nil)) }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        let strip = UIScrollView()
        strip.showsHorizontalScrollIndicator = false
        row.translatesAutoresizingMaskIntoConstraints = false
        strip.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: strip.contentLayoutGuide.topAnchor),
            row.leadingAnchor.constraint(equalTo: strip.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: strip.contentLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: strip.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: strip.frameLayoutGuide.heightAnchor),
            strip.heightAnchor.constraint(equalToConstant: 146)
        ])
        let column = UIStackView(arrangedSubviews: [header, strip])
        column.axis = .vertical
        column.spacing = 8
        return column
    }

    private func actions() -> UIView {
        let primary = UIButton.primaryButton(title: MilestoneCopy.primaryAction(milestone))
        primary.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.open(URL(string: "\(ShareLinks.base)/app/open?path=\(MilestoneCopy.primaryPath(self.milestone))")!)
        }, for: .touchUpInside)
        let share = UIButton.secondaryButton(title: "Share")
        share.addAction(UIAction { [weak self] _ in self?.shareTapped(share) }, for: .touchUpInside)
        let column = UIStackView(arrangedSubviews: [primary, share])
        column.axis = .vertical
        column.spacing = 10
        return column
    }

    private func sectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 17, weight: .bold)
        label.numberOfLines = 0
        return label
    }

    private func shareTapped(_ source: UIView) {
        let text = MilestoneCopy.shareText(milestone, count: month?.count)
        let activity = UIActivityViewController(activityItems: [text, ShareLinks.appStoreURL], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = source
        present(activity, animated: true)
    }

    /// Close this sheet, then follow the app's own link to wherever it points
    private func open(_ url: URL) {
        let scene = view.window?.windowScene?.delegate as? SceneDelegate
        dismiss(animated: true) { scene?.handleDeepLink(url) }
    }
}
