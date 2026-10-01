import UIKit

/// The photo row at the top of Edit Place: the place's one photo library,
/// cover first, a "+" to add, and a link into the full library — "Arrange ·
/// set cover · remove" for the store's team and admins, "See all" for
/// everyone else (who can add photos and delete their own).
final class PlacePhotoStripView: UIView {
    var onAdd: (() -> Void)?
    var onOpenLibrary: (() -> Void)?
    var onPhotoTapped: ((Int) -> Void)?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .darkGray
        label.text = "Photos"
        return label
    }()
    private let countLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()
    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()
    private let row: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    private lazy var libraryButton: UIButton = {
        let button = UIButton.captionLinkButton()
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(libraryTapped), for: .touchUpInside)
        return button
    }()

    private static let tileSize: CGFloat = 84

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), countLabel])
        header.axis = .horizontal
        let stack = UIStackView(arrangedSubviews: [header, scrollView, libraryButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        scrollView.addSubview(row)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: Self.tileSize),
            row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        configure(urls: [], canManage: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - urls: the library as this person sees it, cover first
    func configure(urls: [String], canManage: Bool) {
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, url) in urls.enumerated() {
            row.addArrangedSubview(thumbnail(url: url, index: index, isCover: index == 0))
        }
        row.addArrangedSubview(addTile())
        countLabel.text = urls.isEmpty ? "None yet" : "\(urls.count)"
        libraryButton.setTitle(canManage ? "Arrange · set cover · remove ›" : (urls.isEmpty ? nil : "See all ›"), for: .normal)
        libraryButton.isHidden = !canManage && urls.isEmpty
    }

    private func thumbnail(url: String, index: Int, isCover: Bool) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.backgroundColor = .secondarySystemBackground
        imageView.isUserInteractionEnabled = true
        imageView.tag = index
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: Self.tileSize).isActive = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(photoTapped(_:))))
        imageView.accessibilityLabel = isCover ? "Cover photo" : "Photo \(index + 1)"
        ImageService.shared.loadImage(from: url) { [weak imageView] image in
            DispatchQueue.main.async { imageView?.image = image }
        }
        if isCover {
            let badge = UILabel()
            badge.text = " Cover "
            badge.font = .systemFont(ofSize: 10, weight: .semibold)
            badge.textColor = .white
            badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            badge.layer.cornerRadius = 4
            badge.clipsToBounds = true
            badge.translatesAutoresizingMaskIntoConstraints = false
            imageView.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 4),
                badge.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -4)
            ])
        }
        return imageView
    }

    private func addTile() -> UIView {
        let button = UIButton.iconButton(systemName: "plus")
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 8
        button.accessibilityLabel = "Add photos"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Self.tileSize).isActive = true
        button.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        return button
    }

    @objc private func addTapped() { onAdd?() }
    @objc private func libraryTapped() { onOpenLibrary?() }
    @objc private func photoTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag else { return }
        onPhotoTapped?(index)
    }
}
