import UIKit

/// A profile content tab rendered as an Instagram-style 3-column grid of
/// square tiles (Moments, Uploads). Sits inside the profile's outer scroll
/// view, so it doesn't scroll itself: it reports its content height through
/// `onContentHeightChanged` and the host sizes it.
///
/// Subclasses supply the items (`itemCount`, `cell(for:at:)`), what a tap
/// and long-press do, and `activate()` — what to load or refresh when the
/// tab is switched to. The host flips tabs with `setActive(_:)`.
class ProfileGridTabViewController: BaseViewController {
    /// Whose profile; `nil` means the signed-in user.
    var userId: String?
    var resolvedUserId: String? { userId ?? AuthService.shared.getUserId() }

    private(set) var isActiveTab = false
    /// The grid's content height changed (rows added/removed, width settled).
    var onContentHeightChanged: ((CGFloat) -> Void)?

    static let columns: CGFloat = 3
    static let spacing: CGFloat = 2
    /// Height reported while the grid has nothing to show (room for the empty label).
    static let emptyHeight: CGFloat = 100

    let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = ProfileGridTabViewController.spacing
        layout.minimumLineSpacing = ProfileGridTabViewController.spacing
        layout.sectionInset = .zero
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    let emptyLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    // The host's segment switch drives loading; nothing loads on its own.
    override var loadsDataOnViewDidLoad: Bool { false }
    override var reloadsDataOnAppear: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    init(emptyText: String) {
        super.init(nibName: nil, bundle: nil)
        emptyLabel.text = emptyText
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(collectionView)
        view.addSubview(emptyLabel)
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 100),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: emptyLabel.centerYAnchor)
        ])
        collectionView.dataSource = self
        collectionView.delegate = self
        registerCells(in: collectionView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Tile size depends on the grid's width, so re-measure once laid out
        if isActiveTab && itemCount > 0 {
            updateContentHeight()
        }
    }

    // MARK: - Subclass hooks

    func registerCells(in collectionView: UICollectionView) {}
    var itemCount: Int { 0 }
    func cell(for collectionView: UICollectionView, at indexPath: IndexPath) -> UICollectionViewCell {
        UICollectionViewCell()
    }
    func didSelectItem(at index: Int) {}
    func contextMenu(at index: Int) -> UIMenu? { nil }
    /// The tab was switched to: load if needed, else re-render.
    func activate() {}

    // MARK: - Host contract

    func setActive(_ active: Bool) {
        isActiveTab = active
        view.isHidden = !active
        if active {
            activate()
        } else {
            emptyLabel.isHidden = true
            loadingIndicator.stopAnimating()
        }
    }

    // MARK: - Rendering helpers

    func showLoading() {
        emptyLabel.isHidden = true
        loadingIndicator.startAnimating()
    }

    /// Re-render after data changed: reload, resize, and show the empty
    /// label when there's nothing.
    func showLoaded() {
        loadingIndicator.stopAnimating()
        collectionView.reloadData()
        updateContentHeight()
        emptyLabel.isHidden = itemCount > 0
    }

    /// Grid height for the current item count: rows of square tiles plus a
    /// little padding, or a fixed minimum when empty.
    func updateContentHeight() {
        onContentHeightChanged?(Self.gridHeight(itemCount: itemCount, width: gridWidth))
    }

    private var gridWidth: CGFloat {
        collectionView.bounds.width > 0 ? collectionView.bounds.width : UIScreen.main.bounds.width
    }

    static func gridHeight(itemCount: Int, width: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return emptyHeight }
        let itemWidth = (width - spacing * (columns - 1)) / columns
        let rows = ceil(Double(itemCount) / Double(columns))
        return CGFloat(rows) * itemWidth + spacing * (CGFloat(rows) - 1) + 20
    }
}

// MARK: - Collection view

extension ProfileGridTabViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        itemCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        cell(for: collectionView, at: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < itemCount else { return }
        didSelectItem(at: indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.item < itemCount, let menu = contextMenu(at: indexPath.item) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // Square tiles, three across
        let itemWidth = (collectionView.bounds.width - Self.spacing * (Self.columns - 1)) / Self.columns
        return CGSize(width: itemWidth, height: itemWidth)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        Self.spacing
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        Self.spacing
    }
}
