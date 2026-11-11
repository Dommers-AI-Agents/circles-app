import UIKit

/// "Hold up your phone": a big QR the person across the table scans with
/// their Camera (Scan Actions, Wes 2026-11-11, at brunch). One place, a set
/// of places, a "show me how" guide or a store owner's setup. The screen goes
/// to full brightness while it's up, so the code scans in sunlight.
final class ScanCodeSheetViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { true }

    /// Makes (or names) the code: a call to the server, or a fixed guide link
    typealias Maker = (@escaping (Result<ScanActionCreated, Error>) -> Void) -> Void

    private let headline: String
    private let explainer: String
    private let maker: Maker
    private var created: ScanActionCreated?
    private var savedBrightness: CGFloat?

    private let card = UIView()
    private let qrView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let noteLabel = UILabel()
    private let codeLabel = UILabel()
    private lazy var shareButton = UIButton.secondaryButton(title: "Send the Link")
    private lazy var doneButton = UIButton.primaryButton(title: "Done")

    init(title: String, explainer: String, maker: @escaping Maker) {
        self.headline = title
        self.explainer = explainer
        self.maker = maker
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Presenting

    private static func present(_ sheet: ScanCodeSheetViewController, from host: UIViewController) {
        let nav = UINavigationController(rootViewController: sheet)
        nav.modalPresentationStyle = .pageSheet
        if let presentation = nav.sheetPresentationController {
            presentation.detents = [.large()]
            presentation.prefersGrabberVisible = true
        }
        host.present(nav, animated: true)
    }

    /// One place: they scan, pick a circle, it's saved
    static func presentPlace(_ place: Place, from host: UIViewController) {
        let sheet = ScanCodeSheetViewController(
            title: place.name,
            explainer: "Hold up your phone. They scan it with their Camera, pick a circle, and \(place.name) is on their map. No FavCircles yet? It still opens."
        ) { done in
            ScanActionService.shared.createPlace(saveId: place.id, globalPlaceId: place.globalPlaceId, completion: done)
        }
        present(sheet, from: host)
    }

    /// A list (a filtered circle or Home view), frozen as it is now
    static func presentSet(title: String, places: [Place], source: [String: String], from host: UIViewController) {
        let ids = places.map(\.id)
        let count = min(ids.count, ScanActionService.maxSetPlaces)
        let capped = ScanActionCopy.capped(total: ids.count, max: ScanActionService.maxSetPlaces)
        let sheet = ScanCodeSheetViewController(
            title: title,
            explainer: "Hold up your phone. They scan it, tick the ones they want, and the \(count == 1 ? "place goes" : "places go") on their map."
                + (capped.map { " \($0)" } ?? "")
        ) { done in
            ScanActionService.shared.createSet(title: title, saveIds: ids, source: source, completion: done)
        }
        present(sheet, from: host)
    }

    /// A "show me how" guide: a fixed link, nothing to make
    static func presentGuide(id: String, title: String, blurb: String, from host: UIViewController) {
        let sheet = ScanCodeSheetViewController(
            title: title,
            explainer: "\(blurb) Whoever scans this gets walked through it, step by step, in their FavCircles."
        ) { done in
            done(.success(ScanActionCreated(code: id, url: ScanActionLink.url(code: id).absoluteString, kind: "guide",
                                            title: title, expiresAt: nil, leftOutPrivate: nil, leftOutHidden: nil, places: nil)))
        }
        present(sheet, from: host)
    }

    /// A store owner's setup, made for one store (super-users). Whoever
    /// redeems it first becomes the owner.
    static func presentStoreSetup(venueId: String?, globalPlaceId: String?, storeName: String, from host: UIViewController) {
        let sheet = ScanCodeSheetViewController(
            title: "Set up \(storeName)",
            explainer: "For the owner. They scan it, \(storeName) becomes theirs, and FavCircles walks them through points, a first reward and their window QR. One use; works for 14 days."
        ) { done in
            ScanActionService.shared.createStoreSetup(venueId: venueId, globalPlaceId: globalPlaceId, completion: done)
        }
        present(sheet, from: host)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.groupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(doneTapped))
        navigationItem.largeTitleDisplayMode = .never
        buildLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        brighten(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        brighten(false)
    }

    override func loadData(completion: (() -> Void)? = nil) {
        card.isHidden = true
        maker { [weak self] result in
            completion?()
            guard let self else { return }
            switch result {
            case .success(let created):
                self.show(created)
            case .failure(let error):
                AlertPresenter.showError(message: (error as? ScanActionService.Refusal)?.message ?? FriendlyError.message(for: error),
                                         from: self) { [weak self] in self?.dismiss(animated: true) }
            }
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        card.backgroundColor = .white
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        card.isHidden = true

        qrView.contentMode = .scaleAspectFit
        qrView.layer.magnificationFilter = .nearest
        qrView.isAccessibilityElement = true
        qrView.accessibilityLabel = "QR code"
        qrView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = headline
        titleLabel.font = UIFont(descriptor: UIFont.systemFont(ofSize: 26, weight: .bold).fontDescriptor.withDesign(.serif) ?? UIFont.systemFont(ofSize: 26).fontDescriptor, size: 26)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        codeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        codeLabel.textColor = .darkGray
        codeLabel.textAlignment = .center

        let cardStack = UIStackView(arrangedSubviews: [titleLabel, qrView, codeLabel])
        cardStack.axis = .vertical
        cardStack.alignment = .center
        cardStack.spacing = 14
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)

        bodyLabel.text = explainer
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = Constants.Colors.secondaryLabel
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        noteLabel.font = .preferredFont(forTextStyle: .footnote)
        noteLabel.adjustsFontForContentSizeCategory = true
        noteLabel.textColor = Constants.Colors.secondaryLabel
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0
        noteLabel.isHidden = true

        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        shareButton.isEnabled = false

        let buttons = UIStackView(arrangedSubviews: [shareButton, doneButton])
        buttons.axis = .vertical
        buttons.spacing = 10

        let page = UIStackView(arrangedSubviews: [card, bodyLabel, noteLabel, buttons])
        page.axis = .vertical
        page.spacing = 18
        page.setCustomSpacing(10, after: bodyLabel)
        page.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(page)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            page.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            page.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            page.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            page.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),

            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            qrView.widthAnchor.constraint(equalTo: cardStack.widthAnchor, multiplier: 0.86),
            qrView.heightAnchor.constraint(equalTo: qrView.widthAnchor)
        ])
    }

    private func show(_ created: ScanActionCreated) {
        self.created = created
        if let code = QRCodeRenderer.image(for: created.url, correction: "H") {
            qrView.image = QRCodeRenderer.withLogo(code)
        }
        codeLabel.text = created.code.count == 8 ? "Code \(created.code)" : nil
        codeLabel.isHidden = codeLabel.text == nil
        let leftOut = ScanActionCopy.leftOut(privateCount: created.leftOutPrivate ?? 0, hiddenCount: created.leftOutHidden ?? 0)
        noteLabel.text = leftOut
        noteLabel.isHidden = leftOut == nil
        card.isHidden = false
        shareButton.isEnabled = true
        UIAccessibility.post(notification: .screenChanged, argument: qrView)
    }

    // MARK: - Brightness

    private func brighten(_ on: Bool) {
        guard let screen = view.window?.windowScene?.screen else { return }
        if on {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 1
        } else if let saved = savedBrightness {
            screen.brightness = saved
            savedBrightness = nil
        }
    }

    // MARK: - Actions

    @objc private func shareTapped() {
        guard let created, let url = URL(string: created.url) else { return }
        // One bubble: the link with its preview filled in, no extra text
        let item = LinkPreviewItem(url: url, title: created.title ?? headline, image: qrView.image)
        let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = shareButton
        present(sheet, animated: true)
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}
