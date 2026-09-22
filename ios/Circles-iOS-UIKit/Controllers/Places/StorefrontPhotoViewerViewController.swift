import UIKit

/// Full-screen pager for the owner's menu and gallery photos. Deliberately
/// small: swipe between pages, pinch to zoom one, tap to close.
final class StorefrontPhotoViewerViewController: BaseViewController {
    private let urls: [String]
    private let startIndex: Int

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

    init(urls: [String], startingAt index: Int) {
        self.urls = urls
        self.startIndex = max(0, min(index, urls.count - 1))
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
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
        NSLayoutConstraint.activate([
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
    }
}
