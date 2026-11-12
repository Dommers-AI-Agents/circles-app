import UIKit

/// Full-screen pager for a place's photos (the place page's carousel and
/// Photos section, the gallery, the owner's menu). Deliberately small: swipe
/// between pages, pinch or double-tap to zoom one, tap to close. A page whose
/// photo is in the place's library carries a heart, so a photo can be liked
/// from any view (Wes, 2026-11-05), and a "•••" menu to report it
/// (Wes, 2026-11-12: there was no way to report a photo from here).
final class StorefrontPhotoViewerViewController: BaseViewController {
    private let urls: [String]
    private let startIndex: Int
    /// The venue the photos belong to and its library photos, matched to
    /// pages by URL; empty = no hearts
    private let placeId: String?
    private let libraryPhotos: [String: AttributedPhoto]
    private let onLikeChanged: (() -> Void)?
    /// Optimistic like state per photo id, seeded from the library
    private var likeState: [String: (liked: Bool, count: Int)] = [:]
    private var currentPage = 0
    private lazy var likeButton: UIButton = {
        let button = UIButton.iconButton(systemName: "heart")
        button.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        button.layer.cornerRadius = 18
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        button.accessibilityLabel = "Like photo"
        return button
    }()

    /// "•••" → Report, on pages showing someone else's library photo
    private lazy var moreButton: UIButton = {
        let button = UIButton.iconButton(systemName: "ellipsis.circle.fill")
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = "More"
        return button
    }()

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private lazy var pager: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.isPagingEnabled = true
        cv.backgroundColor = .black
        cv.showsHorizontalScrollIndicator = false
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(PageCell.self, forCellWithReuseIdentifier: "Page")
        cv.dataSource = self
        cv.delegate = self
        return cv
    }()
    private let counter = UILabel()

    /// - Parameters:
    ///   - placeId: the venue (globalPlaces) id the library photos belong to
    ///   - libraryPhotos: the place's library; pages showing one of them get a heart
    ///   - onLikeChanged: after a like is saved, so the presenter can refresh
    init(urls: [String], startingAt index: Int, placeId: String? = nil,
         libraryPhotos: [AttributedPhoto] = [], onLikeChanged: (() -> Void)? = nil) {
        self.urls = urls
        self.startIndex = max(0, min(index, urls.count - 1))
        self.placeId = placeId
        var byURL: [String: AttributedPhoto] = [:]
        for photo in libraryPhotos where photo.photoId != nil {
            byURL[Self.urlKey(photo.url)] = photo
        }
        self.libraryPhotos = placeId == nil ? [:] : byURL
        self.onLikeChanged = onLikeChanged
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        let me = AuthService.shared.getUserId() ?? ""
        for photo in byURL.values {
            guard let photoId = photo.photoId else { continue }
            likeState[photoId] = (liked: (photo.likes ?? []).contains(me),
                                  count: photo.likesCount ?? photo.likes?.count ?? 0)
        }
    }

    /// Same photo, any token/query string
    private static func urlKey(_ url: String) -> String { url.components(separatedBy: "?").first ?? url }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addSubview(pager)
        let close = UIButton.iconButton(systemName: "xmark.circle.fill")
        close.tintColor = .white
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(close)
        counter.textColor = .white
        counter.font = .systemFont(ofSize: 13, weight: .medium)
        counter.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(counter)
        view.addSubview(likeButton)
        view.addSubview(moreButton)
        NSLayoutConstraint.activate([
            moreButton.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            moreButton.widthAnchor.constraint(equalToConstant: 36),
            moreButton.heightAnchor.constraint(equalToConstant: 36),
            likeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            likeButton.centerYAnchor.constraint(equalTo: counter.centerYAnchor),
            likeButton.heightAnchor.constraint(equalToConstant: 36),
            pager.topAnchor.constraint(equalTo: view.topAnchor),
            pager.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pager.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            close.widthAnchor.constraint(equalToConstant: 36),
            close.heightAnchor.constraint(equalToConstant: 36),
            counter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            counter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        updateCounter(startIndex)
        currentPage = startIndex
        updateLikeButton()

        // Double-tap zooms the photo on screen; a single tap closes, but only
        // once it's clear the tap wasn't the first half of a double
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        pager.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        singleTap.require(toFail: doubleTap)
        pager.addGestureRecognizer(singleTap)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: pager)
        guard let indexPath = pager.indexPathForItem(at: point),
              let cell = pager.cellForItem(at: indexPath) as? PageCell else { return }
        cell.toggleZoom(at: gesture.location(in: cell))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = pager.collectionViewLayout as? UICollectionViewFlowLayout, layout.itemSize != pager.bounds.size {
            layout.itemSize = pager.bounds.size
            layout.invalidateLayout()
            pager.scrollToItem(at: IndexPath(item: startIndex, section: 0), at: .centeredHorizontally, animated: false)
        }
    }

    private func updateCounter(_ index: Int) {
        counter.text = urls.count > 1 ? "\(index + 1) of \(urls.count)" : nil
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    // MARK: - Likes

    private func photo(at page: Int) -> AttributedPhoto? {
        guard urls.indices.contains(page) else { return nil }
        return libraryPhotos[Self.urlKey(urls[page])]
    }

    private func updateLikeButton() {
        updateMoreButton()
        guard let photoId = photo(at: currentPage)?.photoId, let state = likeState[photoId] else {
            likeButton.isHidden = true
            return
        }
        likeButton.isHidden = false
        let symbol = state.liked ? "heart.fill" : "heart"
        likeButton.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        likeButton.setTitle(state.count > 0 ? " \(state.count)" : nil, for: .normal)
        likeButton.setTitleColor(.white, for: .normal)
        likeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        likeButton.tintColor = state.liked ? .systemRed : .white
        likeButton.accessibilityLabel = state.liked ? "Unlike photo" : "Like photo"
    }

    // MARK: - Report

    private func updateMoreButton() {
        guard let placeId, let photo = photo(at: currentPage), let photoId = photo.photoId,
              PlacePhotoActions.actions(photo: photo, isCover: false,
                                        viewerId: AuthService.shared.getUserId(), canManage: false).contains(.report) else {
            moreButton.isHidden = true
            moreButton.menu = nil
            return
        }
        moreButton.isHidden = false
        moreButton.menu = UIMenu(children: [
            UIAction(title: "Report or block…", image: UIImage(systemName: "flag"), attributes: .destructive) { [weak self] _ in
                guard let self else { return }
                self.presentContentModerationSheet(
                    contentType: "place_photo",
                    contentId: PlacePhotoActions.reportContentId(placeId: placeId, photoId: photoId),
                    ownerId: photo.uploadedBy ?? "",
                    ownerName: photo.uploadedByName,
                    sourceView: self.moreButton
                )
            }
        ])
    }

    @objc private func likeTapped() {
        guard let placeId, let photoId = photo(at: currentPage)?.photoId,
              var state = likeState[photoId] else { return }
        // Optimistic, like the carousel's heart; put back if the save fails
        state.liked.toggle()
        state.count = max(0, state.count + (state.liked ? 1 : -1))
        likeState[photoId] = state
        updateLikeButton()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let liked = state.liked
        GlobalPlaceService.shared.setPhotoLiked(placeId: placeId, photoId: photoId, liked: liked) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let response):
                    // First like on someone else's photo earns a nickel
                    if liked { PiggyBankDepositView.play(credit: response.piggyBank) }
                    self.onLikeChanged?()
                case .failure:
                    var back = state
                    back.liked.toggle()
                    back.count = max(0, back.count + (back.liked ? 1 : -1))
                    self.likeState[photoId] = back
                    self.updateLikeButton()
                }
            }
        }
    }

    final class PageCell: UICollectionViewCell, UIScrollViewDelegate {
        private let scroll = UIScrollView()
        private let imageView = UIImageView()
        override init(frame: CGRect) {
            super.init(frame: frame)
            scroll.frame = contentView.bounds
            scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scroll.minimumZoomScale = 1
            scroll.maximumZoomScale = 4
            scroll.delegate = self
            scroll.showsVerticalScrollIndicator = false
            scroll.showsHorizontalScrollIndicator = false
            contentView.addSubview(scroll)
            imageView.frame = scroll.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.contentMode = .scaleAspectFit
            scroll.addSubview(imageView)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(_ url: String) {
            scroll.zoomScale = 1
            imageView.image = nil
            ImageService.shared.loadImage(from: url) { [weak self] image in
                DispatchQueue.main.async { self?.imageView.image = image }
            }
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func toggleZoom(at point: CGPoint) {
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let scale: CGFloat = 2.5
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}

extension StorefrontPhotoViewerViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { urls.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Page", for: indexPath) as! PageCell
        cell.configure(urls[indexPath.item])
        return cell
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / max(1, scrollView.bounds.width)))
        updateCounter(page)
        currentPage = page
        updateLikeButton()
    }
}
