import UIKit
import MapKit

protocol VisitCellDelegate: AnyObject {
    func visitCell(_ cell: VisitCell, didToggleSelection visit: PlaceVisit)
    func visitCell(_ cell: VisitCell, didTapQuickAdd visit: PlaceVisit)
    func visitCell(_ cell: VisitCell, didTapDismiss visit: PlaceVisit)
}

class VisitCell: UITableViewCell {
    
    // MARK: - Properties
    weak var delegate: VisitCellDelegate?
    private var visit: PlaceVisit?
    
    var isInSelectionMode = false {
        didSet {
            updateSelectionUI()
        }
    }
    
    var isVisitSelected = false {
        didSet {
            selectionCheckbox.isSelected = isVisitSelected
        }
    }
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.05
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let mapSnapshotView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.backgroundColor = .tertiarySystemFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let placeNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let visitInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var quickAddButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.addTarget(self, action: #selector(quickAddTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var selectionCheckbox: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "circle"), for: .normal)
        button.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .selected)
        button.tintColor = Constants.Colors.primary
        button.addTarget(self, action: #selector(toggleSelection), for: .touchUpInside)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        button.tintColor = .systemRed
        button.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupCell() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.addSubview(mapSnapshotView)
        containerView.addSubview(placeNameLabel)
        containerView.addSubview(addressLabel)
        containerView.addSubview(visitInfoLabel)
        containerView.addSubview(statusBadge)
        containerView.addSubview(quickAddButton)
        containerView.addSubview(selectionCheckbox)
        containerView.addSubview(dismissButton)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            mapSnapshotView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            mapSnapshotView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            mapSnapshotView.widthAnchor.constraint(equalToConstant: 60),
            mapSnapshotView.heightAnchor.constraint(equalToConstant: 60),
            
            placeNameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            placeNameLabel.leadingAnchor.constraint(equalTo: mapSnapshotView.trailingAnchor, constant: 12),
            placeNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusBadge.leadingAnchor, constant: -8),
            
            addressLabel.topAnchor.constraint(equalTo: placeNameLabel.bottomAnchor, constant: 4),
            addressLabel.leadingAnchor.constraint(equalTo: placeNameLabel.leadingAnchor),
            addressLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -50),
            
            visitInfoLabel.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 4),
            visitInfoLabel.leadingAnchor.constraint(equalTo: placeNameLabel.leadingAnchor),
            visitInfoLabel.trailingAnchor.constraint(equalTo: addressLabel.trailingAnchor),
            
            statusBadge.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            statusBadge.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            statusBadge.heightAnchor.constraint(equalToConstant: 20),
            statusBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            quickAddButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            quickAddButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            quickAddButton.widthAnchor.constraint(equalToConstant: 32),
            quickAddButton.heightAnchor.constraint(equalToConstant: 32),
            
            selectionCheckbox.centerXAnchor.constraint(equalTo: quickAddButton.centerXAnchor),
            selectionCheckbox.centerYAnchor.constraint(equalTo: quickAddButton.centerYAnchor),
            selectionCheckbox.widthAnchor.constraint(equalToConstant: 32),
            selectionCheckbox.heightAnchor.constraint(equalToConstant: 32),
            
            dismissButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            dismissButton.trailingAnchor.constraint(equalTo: quickAddButton.leadingAnchor, constant: -8),
            dismissButton.widthAnchor.constraint(equalToConstant: 32),
            dismissButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    // MARK: - Configuration
    func configure(with visit: PlaceVisit) {
        self.visit = visit
        
        placeNameLabel.text = visit.placeName
        addressLabel.text = visit.placeAddress
        
        // Format visit info
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let visitTime = formatter.string(from: visit.visitedAt)
        
        var infoText = visitTime
        if visit.duration > 0 {
            infoText += " • \(visit.duration) min"
        }
        
        // Add accuracy indicator if available
        if let accuracy = visit.horizontalAccuracy {
            let accuracyText: String
            if accuracy < 10 {
                accuracyText = "📍" // Very accurate
            } else if accuracy < 25 {
                accuracyText = "📍" // Good accuracy
            } else if accuracy < 50 {
                accuracyText = "📍" // Fair accuracy  
            } else {
                accuracyText = "📍" // Poor accuracy
            }
            infoText += " \(accuracyText)"
        }
        
        visitInfoLabel.text = infoText
        
        // Configure status badge
        if visit.dismissed {
            statusBadge.text = " Dismissed "
            statusBadge.backgroundColor = .systemGray5
            statusBadge.textColor = .systemGray
        } else if visit.reviewed {
            statusBadge.text = " Reviewed "
            statusBadge.backgroundColor = .systemGreen.withAlphaComponent(0.1)
            statusBadge.textColor = .systemGreen
        } else {
            statusBadge.text = " New "
            statusBadge.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
            statusBadge.textColor = Constants.Colors.primary
        }
        
        // Hide dismiss button if already dismissed
        dismissButton.isHidden = visit.dismissed || isInSelectionMode
        
        // Load map snapshot
        loadMapSnapshot(for: visit)
        
        // Update selection UI
        updateSelectionUI()
    }
    
    private func loadMapSnapshot(for visit: PlaceVisit) {
        let location = CLLocationCoordinate2D(
            latitude: visit.latitude,
            longitude: visit.longitude
        )
        
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: location,
            latitudinalMeters: 200,
            longitudinalMeters: 200
        )
        options.size = CGSize(width: 60, height: 60)
        options.scale = UIScreen.main.scale
        
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { [weak self] snapshot, error in
            guard let snapshot = snapshot else { return }
            
            DispatchQueue.main.async {
                self?.mapSnapshotView.image = snapshot.image
            }
        }
    }
    
    private func updateSelectionUI() {
        quickAddButton.isHidden = isInSelectionMode
        selectionCheckbox.isHidden = !isInSelectionMode
        dismissButton.isHidden = isInSelectionMode || visit?.dismissed == true
    }
    
    // MARK: - Actions
    @objc private func quickAddTapped() {
        guard let visit = visit else { return }
        delegate?.visitCell(self, didTapQuickAdd: visit)
    }
    
    @objc private func toggleSelection() {
        guard let visit = visit else { return }
        isVisitSelected.toggle()
        delegate?.visitCell(self, didToggleSelection: visit)
    }
    
    @objc private func dismissTapped() {
        guard let visit = visit else { return }
        delegate?.visitCell(self, didTapDismiss: visit)
    }
}