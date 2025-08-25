import UIKit

class CircleGroupCell: UICollectionViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // 2x2 grid of mini circle cover images (like iOS app folders)
    private let gridContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.tertiaryBackground
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let topLeftImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let topRightImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let bottomLeftImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let bottomRightImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let circleCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Visual separator between grid and images
    private let separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.separator.withAlphaComponent(0.3)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Folder-like visual indicator
    private let groupIndicatorView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "folder.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        imageView.tintColor = Constants.Colors.primary.withAlphaComponent(0.8)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    // Drag state visual feedback
    private var isInDragState = false
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        contentView.addSubview(containerView)
        containerView.addSubview(gridContainerView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(circleCountLabel)
        containerView.addSubview(groupIndicatorView)
        
        // Add 2x2 grid of image views
        gridContainerView.addSubview(topLeftImageView)
        gridContainerView.addSubview(topRightImageView)
        gridContainerView.addSubview(bottomLeftImageView)
        gridContainerView.addSubview(bottomRightImageView)
        gridContainerView.addSubview(separatorView)
        
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Grid container (circular like CircleCell)
            gridContainerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            gridContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            gridContainerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            gridContainerView.heightAnchor.constraint(equalTo: gridContainerView.widthAnchor), // Keep square
            
            // Top row images
            topLeftImageView.topAnchor.constraint(equalTo: gridContainerView.topAnchor),
            topLeftImageView.leadingAnchor.constraint(equalTo: gridContainerView.leadingAnchor),
            topLeftImageView.widthAnchor.constraint(equalTo: gridContainerView.widthAnchor, multiplier: 0.5),
            topLeftImageView.heightAnchor.constraint(equalTo: gridContainerView.heightAnchor, multiplier: 0.5),
            
            topRightImageView.topAnchor.constraint(equalTo: gridContainerView.topAnchor),
            topRightImageView.trailingAnchor.constraint(equalTo: gridContainerView.trailingAnchor),
            topRightImageView.widthAnchor.constraint(equalTo: gridContainerView.widthAnchor, multiplier: 0.5),
            topRightImageView.heightAnchor.constraint(equalTo: gridContainerView.heightAnchor, multiplier: 0.5),
            
            // Bottom row images
            bottomLeftImageView.bottomAnchor.constraint(equalTo: gridContainerView.bottomAnchor),
            bottomLeftImageView.leadingAnchor.constraint(equalTo: gridContainerView.leadingAnchor),
            bottomLeftImageView.widthAnchor.constraint(equalTo: gridContainerView.widthAnchor, multiplier: 0.5),
            bottomLeftImageView.heightAnchor.constraint(equalTo: gridContainerView.heightAnchor, multiplier: 0.5),
            
            bottomRightImageView.bottomAnchor.constraint(equalTo: gridContainerView.bottomAnchor),
            bottomRightImageView.trailingAnchor.constraint(equalTo: gridContainerView.trailingAnchor),
            bottomRightImageView.widthAnchor.constraint(equalTo: gridContainerView.widthAnchor, multiplier: 0.5),
            bottomRightImageView.heightAnchor.constraint(equalTo: gridContainerView.heightAnchor, multiplier: 0.5),
            
            // Subtle separators between images
            separatorView.centerXAnchor.constraint(equalTo: gridContainerView.centerXAnchor),
            separatorView.centerYAnchor.constraint(equalTo: gridContainerView.centerYAnchor),
            separatorView.widthAnchor.constraint(equalToConstant: 1),
            separatorView.heightAnchor.constraint(equalTo: gridContainerView.heightAnchor),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: gridContainerView.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            
            // Circle count label
            circleCountLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            circleCountLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
            circleCountLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            circleCountLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -4),
            
            // Group indicator (small folder icon in corner)
            groupIndicatorView.topAnchor.constraint(equalTo: gridContainerView.topAnchor, constant: 6),
            groupIndicatorView.trailingAnchor.constraint(equalTo: gridContainerView.trailingAnchor, constant: -6),
            groupIndicatorView.widthAnchor.constraint(equalToConstant: 16),
            groupIndicatorView.heightAnchor.constraint(equalToConstant: 16)
        ])
        
        // Set initial corner radius
        DispatchQueue.main.async { [weak self] in
            self?.updateCornerRadius()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateCornerRadius()
    }
    
    private func updateCornerRadius() {
        // Make the grid container circular like CircleCell
        let radius = gridContainerView.bounds.width / 2
        if radius > 0 {
            gridContainerView.layer.cornerRadius = radius
        }
    }
    
    // MARK: - Configure
    func configure(with group: CircleGroup) {
        nameLabel.text = group.name
        circleCountLabel.text = group.circleCountText
        
        // Configure the 2x2 grid with up to 4 circle cover images
        let imageViews = [topLeftImageView, topRightImageView, bottomLeftImageView, bottomRightImageView]
        let coverImages = group.displayCoverImages // Always returns 4 elements
        
        for (index, imageView) in imageViews.enumerated() {
            if let coverImageUrl = coverImages[index] {
                // Load the circle's cover image
                ImageService.shared.loadImage(from: coverImageUrl) { image in
                    DispatchQueue.main.async {
                        imageView.image = image
                        imageView.backgroundColor = Constants.Colors.lightGray
                    }
                }
            } else {
                // Show placeholder for empty slots
                imageView.image = nil
                imageView.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.5)
            }
        }
    }
    
    // MARK: - Drag & Drop Visual States
    
    /// Set visual state for when this cell is being dragged
    func setDragState(_ isDragging: Bool) {
        isInDragState = isDragging
        
        UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction]) {
            if isDragging {
                self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                self.alpha = 0.8
                self.layer.shadowColor = UIColor.black.cgColor
                self.layer.shadowOpacity = 0.3
                self.layer.shadowOffset = CGSize(width: 0, height: 4)
                self.layer.shadowRadius = 8
            } else {
                self.transform = .identity
                self.alpha = 1.0
                self.layer.shadowOpacity = 0
            }
        }
    }
    
    /// Set visual state for when another item is being dragged over this cell
    func setDropTargetState(_ isDropTarget: Bool) {
        UIView.animate(withDuration: 0.2) {
            if isDropTarget {
                self.gridContainerView.layer.borderWidth = 2
                self.gridContainerView.layer.borderColor = Constants.Colors.primary.cgColor
                self.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            } else {
                self.gridContainerView.layer.borderWidth = 0
                self.transform = self.isInDragState ? CGAffineTransform(scaleX: 1.1, y: 1.1) : .identity
            }
        }
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Reset visual state
        transform = .identity
        alpha = 1.0
        layer.shadowOpacity = 0
        gridContainerView.layer.borderWidth = 0
        isInDragState = false
        
        // Clear images
        topLeftImageView.image = nil
        topRightImageView.image = nil
        bottomLeftImageView.image = nil
        bottomRightImageView.image = nil
        
        // Reset background colors
        [topLeftImageView, topRightImageView, bottomLeftImageView, bottomRightImageView].forEach {
            $0.backgroundColor = Constants.Colors.lightGray
        }
    }
}