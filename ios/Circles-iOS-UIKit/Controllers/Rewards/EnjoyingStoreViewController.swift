import UIKit

/// "Enjoying <store>?" (Wes, 2026-11-02): once per store, after a reward is
/// given. Never in exchange for the reward, and the same for everyone — it
/// offers a review on FavCircles (a comment on the place), following the
/// store, private feedback to the store, and a moment there.
/// `presentIfFirstTime` asks the server, which answers `show` only once.
final class EnjoyingStoreViewController: BaseViewController {

    private let card: EnjoyingCardData
    private let venueId: String
    private weak var host: UIViewController?

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private var venueName: String { card.venueName ?? "this store" }

    private lazy var reviewButton = UIButton.secondaryButton(title: "Write a review")
    private lazy var followButton = UIButton.secondaryButton(title: "Follow \(venueName)")
    private lazy var privateButton = UIButton.secondaryButton(title: "Tell \(venueName) privately")
    private lazy var momentButton = UIButton.secondaryButton(title: "Post a moment here")
    private lazy var notNowButton = UIButton.secondaryButton(title: "Not now")

    /// After a reward is given: shows the card from `host` if it's the first time at this store.
    static func presentIfFirstTime(venueId: String, from host: UIViewController) {
        RewardsService.shared.enjoyingCard(venueId: venueId) { [weak host] result in
            DispatchQueue.main.async {
                guard let host, case .success(let card) = result, card.show else { return }
                let sheet = EnjoyingStoreViewController(card: card, venueId: venueId, host: host)
                if let presentation = sheet.sheetPresentationController {
                    presentation.detents = [.medium(), .large()]
                    presentation.prefersGrabberVisible = true
                }
                host.present(sheet, animated: true)
            }
        }
    }

    init(card: EnjoyingCardData, venueId: String, host: UIViewController) {
        self.card = card
        self.venueId = venueId
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Enjoying \(venueName)?"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = "Enjoy your reward! If you have a moment, here's how to help \(venueName)."
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        var rows: [UIView] = [titleLabel, bodyLabel]
        if card.reviewPlaceId != nil { rows.append(reviewButton) }
        if card.following != true, card.globalPlaceId != nil { rows.append(followButton) }
        rows.append(privateButton)
        rows.append(momentButton)
        rows.append(notNowButton)

        reviewButton.setImage(UIImage(systemName: "text.bubble"), for: .normal)
        followButton.setImage(UIImage(systemName: "bell"), for: .normal)
        privateButton.setImage(UIImage(systemName: "envelope"), for: .normal)
        momentButton.setImage(UIImage(systemName: "camera"), for: .normal)
        [reviewButton, followButton, privateButton, momentButton].forEach { $0.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0) }

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(6, after: titleLabel)
        stack.setCustomSpacing(16, after: bodyLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24)
        ])

        reviewButton.addTarget(self, action: #selector(reviewTapped), for: .touchUpInside)
        followButton.addTarget(self, action: #selector(followTapped), for: .touchUpInside)
        privateButton.addTarget(self, action: #selector(privateTapped), for: .touchUpInside)
        momentButton.addTarget(self, action: #selector(momentTapped), for: .touchUpInside)
        notNowButton.addTarget(self, action: #selector(notNowTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    /// Close the card, then open `next` from the screen underneath
    private func closeThen(_ next: @escaping (UIViewController) -> Void) {
        let host = self.host
        dismiss(animated: true) {
            if let host { next(host) }
        }
    }

    @objc private func reviewTapped() {
        guard let placeId = card.reviewPlaceId else { return }
        let prompt = "Write a review of \(venueName)"
        closeThen { host in
            PlaceService.shared.fetchPlaceById(id: placeId) { [weak host] result in
                DispatchQueue.main.async {
                    guard let host else { return }
                    switch result {
                    case .success(let place):
                        let comments = PlaceCommentsViewController(place: place)
                        comments.composePrompt = prompt
                        host.present(UINavigationController(rootViewController: comments), animated: true)
                    case .failure(let error):
                        AlertPresenter.showError(error, from: host)
                    }
                }
            }
        }
    }

    @objc private func followTapped() {
        guard let globalPlaceId = card.globalPlaceId else { return }
        followButton.isEnabled = false
        PlaceService.shared.followPlace(id: globalPlaceId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.followButton.setTitle("Following \(self.venueName)", for: .normal)
                    self.followButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
                case .failure(let error):
                    self.followButton.isEnabled = true
                    self.showError(error)
                }
            }
        }
    }

    @objc private func privateTapped() {
        let venueId = self.venueId
        let venueName = self.venueName
        closeThen { host in
            let compose = StoreFeedbackViewController(venueId: venueId, venueName: venueName)
            if let presentation = compose.sheetPresentationController {
                presentation.detents = [.large()]
                presentation.prefersGrabberVisible = true
            }
            host.present(compose, animated: true)
        }
    }

    @objc private func momentTapped() {
        let venueName = self.venueName
        closeThen { host in
            let upload = ContentUploadViewController()
            upload.suggestedPlaceName = venueName
            let nav = UINavigationController(rootViewController: upload)
            nav.modalPresentationStyle = .fullScreen
            host.present(nav, animated: true)
        }
    }

    @objc private func notNowTapped() {
        dismiss(animated: true)
    }
}
