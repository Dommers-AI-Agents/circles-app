import UIKit
import MapKit
import PhotosUI
import AVKit

class PlaceDetailViewController: BaseViewController {
    
    // MARK: - Properties
    private var place: Place
    private var globalPlace: GlobalPlace? // Global place data with attribution
    // Our OWN save of this venue when `place` is another user's copy —
    // private notes read from and write to this record
    private var mySaveOfVenue: Place?
    /// Private notes editor and save (notes live on our OWN save record).
    private lazy var notesEdit: PlaceNotesEditController = {
        let controller = PlaceNotesEditController(presenter: self)
        controller.delegate = self
        return controller
    }()
    private var circle: Circle?
    private var creatorUser: User? // Store the creator user for navigation
    private var userCircles: [Circle] = [] // Store user's circles for check-in detection
    
    // MARK: - Media Services
    private lazy var mediaCaptureService = MediaCaptureService()
    private let mediaProcessingService = MediaProcessingService.shared
    private let mediaStorageService = MediaStorageService.shared
    
    // MARK: - Configuration
    override var loadsDataOnViewDidLoad: Bool { false }
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let mediaCarouselView: MediaCarouselView = {
        let view = MediaCarouselView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        return view
    }()
    
    /// Apple Look Around: availability, snapshot and shown/hidden live in
    /// the controller; these forwarders keep the page's call sites unchanged.
    private lazy var lookAround: PlaceLookAroundController = {
        let controller = PlaceLookAroundController()
        controller.delegate = self
        return controller
    }()
    private var streetViewImage: UIImage? {
        get { lookAround.image }
        set { lookAround.image = newValue }
    }
    private var isStreetViewAvailable: Bool {
        get { lookAround.isAvailable }
        set { lookAround.isAvailable = newValue }
    }
    private var showingStreetView: Bool {
        get { lookAround.isShowing }
        set { lookAround.isShowing = newValue }
    }
    private var customImage: UIImage?
    private var isHomeOrWorkPlace: Bool {
        return (place.circleId == nil || place.circleId?.isEmpty == true) && (place.id == "home-place" || place.id == "work-place")
    }
    private var isLoadingPhoto = false
    // Locally held photos with their storage URL (when known) so the carousel
    // can dedupe them against server-provided photo lists
    private var placePhotos: [(image: UIImage, url: String?)] = []
    private var currentPhotoIndex = 0
    
    private func updateMediaCarousel() {
        Logger.debug("📸 [PlaceDetailViewController] updateMediaCarousel() called for place: \(place.name)")
        // Merge rules (attributed venue photos first with the cover leading,
        // legacy URLs once each, local captures reused, videos after photos,
        // placeholder when empty) live in PlaceMediaAssembler — unit tested.
        var assembler = PlaceMediaAssembler()
        assembler.attributedPhotos = globalPlace?.photos
        assembler.coverPhotoUrl = globalPlace?.coverPhotoUrl
        assembler.legacyPhotoUrls = place.photos
        assembler.localPhotos = placePhotos.map { PlaceMediaAssembler.LocalPhoto(image: $0.image, url: $0.url) }
        assembler.videoUrls = place.videos
        let mediaItems = assembler.assemble()

        Logger.debug("📸 [PlaceDetailViewController] Configuring MediaCarouselView with \(mediaItems.count) items")
        mediaCarouselView.configure(with: mediaItems)
    }
    
    private let streetViewToggleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Street View", for: .normal)
        button.setImage(UIImage(systemName: "person.and.arrow.left.and.arrow.right"), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        button.layer.cornerRadius = 16
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        // Add shadow for better visibility
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.5
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.layer.shadowRadius = 6
        return button
    }()
    
    private let editImageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Add Photo or Video", for: .normal)
        button.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = false  // Show by default
        // Add shadow for better visibility
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.5
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.layer.shadowRadius = 6
        return button
    }()
    
    // Commented out - automatic photo migration now handles this
    /*
    private let updateInfoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Update Place Info", for: .normal)
        button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true  // Hidden by default
        // Add shadow for better visibility
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.5
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.layer.shadowRadius = 6
        return button
    }()
    */
    
    private let infoContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.white
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categoryEditButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "pencil"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let ratingView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        return view
    }()
    
    // Merged social-proof row text: "Added by X · saved by N people".
    // The name is tappable (profile); the row itself opens the savers list.
    private let creatorLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        return label
    }()

    private let savedByView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        return view
    }()

    private let savedByFacepileView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = -8 // Overlapping avatars
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let savedByChevron: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.right"))
        imageView.tintColor = Constants.Colors.gray
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private var savedByHeightConstraint: NSLayoutConstraint?

    /// Add-to-Circle lives inline in the action row (next to Follow), so
    /// showing/hiding it never shifts the layout.
    private func setAddToCircleVisible(_ visible: Bool) {
        addToCircleButton.isHidden = !visible
    }

    // Venue rewards section (offers + owner announcements); collapsed until
    // the by-place lookup finds an enrolled venue
    private let venueRewardsView = PlaceVenueRewardsView()
    private var venueRewardsHeightConstraint: NSLayoutConstraint?
    private var venueRewardsTopConstraint: NSLayoutConstraint?

    // Partner action chips (Delivery / Reserve / Ride) — server-driven catalog,
    // collapsed until the catalog yields groups eligible for this place
    private let partnerActionsRowView = PartnerActionsRowView()
    private var partnerActionsHeightConstraint: NSLayoutConstraint?
    private var partnerActionsTopConstraint: NSLayoutConstraint?

    private var placeVenueData: PlaceVenueData?
    /// Partner chips, the venue rewards/claim card and the GlobalPlace record;
    /// results land in the VenueRewardsLoaderDelegate extension below.
    private lazy var venueLoader: VenueRewardsLoader = {
        let loader = VenueRewardsLoader()
        loader.delegate = self
        return loader
    }()
    /// Verified-owner state and the tap-to-edit flows (see
    /// PlaceOwnerEditController); this page keeps the views and re-renders
    /// through PlaceOwnerEditControllerDelegate.
    private lazy var ownerEdit = PlaceOwnerEditController(
        fields: PlaceOwnerEditableFields(
            nameLabel: nameLabel, addressLabel: addressLabel,
            categoryLabel: categoryLabel, categoryEditButton: categoryEditButton,
            descriptionLabel: descriptionLabel, aboutTitleLabel: aboutTitleLabel,
            aboutStackView: aboutStackView),
        host: self)

    // Practical actions row: Directions / Website / Call / Edit
    private let practicalButtonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private static func practicalButton(title: String, systemName: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.setTitle(" \(title)", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.tintColor = Constants.Colors.primary
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.backgroundColor = Constants.Colors.secondaryBackground
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // Edit (own places) and Report (others' places) live in the ••• menu
    private let directionsRowButton = PlaceDetailViewController.practicalButton(title: "Directions", systemName: "location.north.line")
    // Check In leads the row: it's the engagement action, the rest are utilities.
    // Same icon as every check-in surface (UIImage.checkInIcon).
    private let checkInRowButton: UIButton = {
        let button = PlaceDetailViewController.practicalButton(title: "Check In", systemName: "checkmark.circle")
        button.setImage(.checkInIcon, for: .normal)
        return button
    }()

    // Add to Circle: compact pill in the action row, left of Follow — same
    // size and style family (they're sibling actions; this one also picks
    // the circle)
    private lazy var addToCircleButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Add to My Circle", style: .primary)
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        button.isHidden = true // Hidden until eligibility is known
        return button
    }()
    
    // MARK: - Action Buttons Container
    private let actionButtonsContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Bold, larger config so the like / comment / send icons read as prominent
    // action buttons rather than thin hairline glyphs.
    static let actionIconConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)

    private let likeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "heart", withConfiguration: PlaceDetailViewController.actionIconConfig), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let likeCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.gray
        label.text = ""
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        return label
    }()
    
    private let commentButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "bubble.left", withConfiguration: PlaceDetailViewController.actionIconConfig), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let commentCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.gray
        label.text = ""
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Send-arrow: fires the same standard share as the nav-bar share button
    // (shareButtonTapped), sitting inline with like/comment like Instagram.
    private let sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "paperplane.fill", withConfiguration: PlaceDetailViewController.actionIconConfig), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var followButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Follow", style: .primary)
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        return button
    }()

    // Follow state survives place reassignment (like/refresh responses may not
    // carry isFollowing) — seeded from the server copy, updated optimistically
    private var isFollowingPlace = false
    private var placeFollowersCount = 0
    
    // MARK: - Comments Section UI
    private let commentsSection: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true // Initially hidden until comments are loaded
        return view
    }()
    
    private let commentsSectionTitle: UILabel = {
        let label = UILabel()
        label.text = "Comments"
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let viewAllCommentsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("View all", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let commentsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private var displayedComments: [PlaceComment] = []
    
    private let ratingImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "star.fill")
        imageView.tintColor = UIColor(hex: "#F6E05E") // Yellow
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let ratingLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        return label
    }()

    /// The saver's personal 0–10 score ("Your rating: 8/10" / "Wes's rating:
    /// 8/10") — distinct from the Google rating chip above
    private let userRatingLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = Constants.Colors.primary
        label.numberOfLines = 1
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let hoursLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // About card: description + hours in one grouped card (phone/website live
    // only in the quick-action chips, not repeated as text)
    private let aboutCardView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let aboutStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let aboutTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "ABOUT"
        label.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        label.textColor = Constants.Colors.secondaryLabel
        return label
    }()

    private var aboutTopConstraint: NSLayoutConstraint?
    private var aboutHeightConstraint: NSLayoutConstraint?

    // Saver count feeds the merged "Added by X · saved by N people" row
    private var savedByCount = 0

    // Places imported via Apple Maps stored contact info only inside the
    // description text ("Phone: …" / "Website: …") — recover it so the
    // quick-action chips can own it and the About card doesn't repeat it.
    // Computed (not lazy): an owner's contact save must refresh these.
    private var effectivePhone: String? {
        place.phone ?? Self.descriptionValue(in: place.description, prefix: "Phone:")
    }

    private var effectiveWebsite: String? {
        place.website ?? Self.descriptionValue(in: place.description, prefix: "Website:")
    }

    private static func descriptionValue(in description: String?, prefix: String) -> String? {
        guard let description = description else { return nil }
        for line in description.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                let value = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.layer.cornerRadius = 12
        mapView.clipsToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        return mapView
    }()
    
    private let notesTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Notes"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notesButtonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Constants.Spacing.small
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let notesEditButton: UIButton = {
        let button = UIButton(type: .system)
        
        // Create configuration for button with icon
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "pencil.circle")
        config.title = "Edit"
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        
        button.configuration = config
        button.configurationUpdateHandler = { button in
            var config = button.configuration
            config?.baseForegroundColor = Constants.Colors.primary
            button.configuration = config
        }
        
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let notesLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addNotesButton: UIButton = {
        let button = UIButton(type: .system)
        
        // Create configuration for button with icon
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "plus.circle")
        config.title = "Add Note"
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        
        button.configuration = config
        button.configurationUpdateHandler = { button in
            var config = button.configuration
            config?.baseForegroundColor = Constants.Colors.primary
            button.configuration = config
        }
        
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    // MARK: - Photos Section UI Elements
    private let photosTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Photos"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let photosButtonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Constants.Spacing.small
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let photosEditButton: UIButton = {
        let button = UIButton(type: .system)
        
        // Create configuration for button with icon
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "pencil.circle")
        config.title = "Add Photo or Video"
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        
        button.configuration = config
        button.configurationUpdateHandler = { button in
            var config = button.configuration
            config?.baseForegroundColor = Constants.Colors.primary
            button.configuration = config
        }
        
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let addPhotoButton: UIButton = {
        let button = UIButton(type: .system)
        
        // Create configuration for button with icon
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "camera.fill")
        config.title = "Add Photo"
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        
        button.configuration = config
        button.configurationUpdateHandler = { button in
            var config = button.configuration
            config?.baseForegroundColor = Constants.Colors.primary
            button.configuration = config
        }
        
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let tagsTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Tags"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tagsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Constants.Spacing.small
        stackView.alignment = .leading
        stackView.distribution = .fillProportionally
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    
    private let websiteButton = PlaceDetailViewController.practicalButton(title: "Website", systemName: "globe")

    private let phoneButton = PlaceDetailViewController.practicalButton(title: "Call", systemName: "phone")
    
    private let circleInfoView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let circleNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let circleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("View Circle", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Init
    
    init(place: Place, circle: Circle? = nil) {
        self.place = place
        self.circle = circle
        super.init(nibName: nil, bundle: nil)
        
        Logger.debug("PlaceDetailViewController init for place: \(place.name)")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Set before pushing when the tap that got here was ABOUT a comment
    /// ("X commented on…", "X liked a comment on…") — lands the user in the
    /// comments instead of at the top of the place page.
    var showCommentsOnAppear = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if showCommentsOnAppear {
            showCommentsOnAppear = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.commentButtonTapped()
            }
        }
    }

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.debug("PlaceDetailViewController viewDidLoad")
        
        // Set up media capture service
        mediaCaptureService.delegate = self
        
        // Track place viewed event
        AnalyticsService.shared.logEvent(AnalyticsService.Events.placeViewed, parameters: [
            "place_id": place.id,
            "place_name": place.name,
            "has_circle": place.circleId != nil
        ])
        
        // Configure scroll view behavior
        scrollView.contentInsetAdjustmentBehavior = .automatic
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        
        // If circle is not provided and circleId is not empty, fetch it
        if circle == nil && place.circleId != nil && !place.circleId!.isEmpty {
            fetchCircle()
        }

        // Load user's circles for check-in detection
        loadUserCircles()

        // Free Apple Look Around street imagery: auto-shows for photo-less
        // places, otherwise arms the Photos/Look Around toggle. This whole
        // pipeline existed but was never invoked — "street view" silently
        // never fired anywhere in the app.
        autoLoadStreetView()
        
        // Try to load GlobalPlace data for better attribution
        loadGlobalPlaceData()

        // Rewards venue (offers + announcements), if this place has one
        loadVenueRewards()

        // Partner action chips (Delivery / Reserve / Ride), if any apply
        loadPartnerActions()

        // Load who saved this place for the saved-by row
        loadPlaceSavers()

        // The place object handed in by the parent list can be stale (lists
        // don't refetch) — refresh it so photos added elsewhere show up
        refreshPlaceFromServer()

        // Viewing another user's copy of a venue we ALSO saved: private notes
        // live on OUR save record, so resolve it for the notes section
        loadMySaveOfVenueIfNeeded()

        setupUI()
        configureUI()
        setupMap()
        
        // Set up media carousel
        updateMediaCarousel()
        mediaCarouselView.delegate = self
        
        // Look Around button removed 2026-08-11: its toggle only relabeled
        // itself — updateMediaCarousel never rendered the street-view image
        
        // Mark place as viewed if it was marked as new
        if place.isNew == true {
            markPlaceAsViewed()
        }
        
        // Rating comes from the canonical venue overlay on the API response;
        // places without one just don't show a rating. (This used to trigger
        // a billed Google Autocomplete + Details lookup on every view of an
        // unrated place.)


        // Listen for place added notification from modal AddPlaceViewController
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaceAddedToCircle(_:)),
            name: Notification.Name("PlaceAddedToCircle"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handlePlaceAddedToCircle(_ notification: Notification) {
        // Place was successfully added from the modal AddPlaceViewController
        // Hide the add button since the place is now in user's circle
        DispatchQueue.main.async { [weak self] in
            self?.setAddToCircleVisible(false)
            self?.updateAddressTitleConstraint()
            
            // Show a subtle success message
            let successView = UIView()
            successView.backgroundColor = Constants.Colors.primary
            successView.layer.cornerRadius = 8
            successView.translatesAutoresizingMaskIntoConstraints = false
            
            let checkIcon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
            checkIcon.tintColor = .white
            checkIcon.translatesAutoresizingMaskIntoConstraints = false
            
            let label = UILabel()
            label.text = "Added to your circle"
            label.textColor = .white
            label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            
            successView.addSubview(checkIcon)
            successView.addSubview(label)
            
            self?.view.addSubview(successView)
            
            NSLayoutConstraint.activate([
                checkIcon.leadingAnchor.constraint(equalTo: successView.leadingAnchor, constant: 12),
                checkIcon.centerYAnchor.constraint(equalTo: successView.centerYAnchor),
                checkIcon.widthAnchor.constraint(equalToConstant: 20),
                checkIcon.heightAnchor.constraint(equalToConstant: 20),
                
                label.leadingAnchor.constraint(equalTo: checkIcon.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: successView.trailingAnchor, constant: -12),
                label.centerYAnchor.constraint(equalTo: successView.centerYAnchor),
                
                successView.bottomAnchor.constraint(equalTo: self?.view.safeAreaLayoutGuide.bottomAnchor ?? successView.bottomAnchor, constant: -20),
                successView.centerXAnchor.constraint(equalTo: self?.view.centerXAnchor ?? successView.centerXAnchor),
                successView.heightAnchor.constraint(equalToConstant: 44)
            ])
            
            successView.alpha = 0
            successView.transform = CGAffineTransform(translationX: 0, y: 20)
            
            UIView.animate(withDuration: 0.3, animations: {
                successView.alpha = 1
                successView.transform = .identity
            }) { _ in
                UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
                    successView.alpha = 0
                    successView.transform = CGAffineTransform(translationX: 0, y: 20)
                }) { _ in
                    successView.removeFromSuperview()
                }
            }
        }
    }
    
    // MARK: - Data Fetching
    
    private func fetchCircle() {
        guard let circleId = place.circleId, !circleId.isEmpty else { return }
        // In a real app, we would fetch circle details from the API using the circle ID
        CircleService.shared.fetchCircleById(id: circleId) { [weak self] result in
            switch result {
            case .success(let circle):
                self?.circle = circle
                DispatchQueue.main.async {
                    self?.updateCircleInfo()
                }
            case .failure(let error):
                Logger.debug("Failed to fetch circle: \(error.localizedDescription)")
            }
        }
    }
    
    private func markPlaceAsViewed() {
        // Mark this place as viewed to clear the red dot
        // Only mark if place belongs to a circle
        guard let circleId = place.circleId, !circleId.isEmpty else {
            Logger.debug("Place has no circleId, skipping mark as viewed")
            return
        }
        
        NetworkManager.shared.markPlaceAsViewed(placeId: place.id, circleId: circleId) { error in
            if let error = error {
                Logger.debug("Error marking place as viewed: \(error)")
            } else {
                Logger.debug("Successfully marked place as viewed")
            }
        }
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        // No nav-bar title: the header block below already leads with the
        // place name — showing it twice wasted the top of the screen
        title = nil

        // Add share button to navigation bar
        let shareBarButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareButtonTapped))
        navigationItem.rightBarButtonItem = shareBarButton
        
        // Add close button if presented modally
        if presentingViewController != nil && navigationController?.viewControllers.first == self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeButtonTapped)
            )
        }
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        // Name row (name + category chip) sits ABOVE the photo, directly on
        // the scroll content — the photo and the info card hang below it
        contentView.addSubview(nameLabel)
        contentView.addSubview(categoryLabel)
        contentView.addSubview(categoryEditButton)

        // Media carousel below the name row
        contentView.addSubview(mediaCarouselView)
        
        // Add photo control buttons on top of image view
        mediaCarouselView.addSubview(editImageButton)
        // mediaCarouselView.addSubview(updateInfoButton) // Commented - automatic migration handles this
        mediaCarouselView.isUserInteractionEnabled = true
        
        // Add info container after image view
        contentView.addSubview(infoContainerView)
        
        infoContainerView.addSubview(ratingView)

        // About card groups description + hours (hidden arranged subviews
        // collapse inside the stack, so partial data needs no special casing)
        infoContainerView.addSubview(aboutCardView)
        aboutCardView.addSubview(aboutStackView)
        aboutStackView.addArrangedSubview(aboutTitleLabel)
        aboutStackView.addArrangedSubview(userRatingLabel)
        aboutStackView.addArrangedSubview(descriptionLabel)
        aboutStackView.addArrangedSubview(hoursLabel)

        // Add tap gesture recognizer for clickable URLs in description
        let descriptionTapGesture = UITapGestureRecognizer(target: self, action: #selector(descriptionLabelTapped(_:)))
        descriptionLabel.addGestureRecognizer(descriptionTapGesture)

        // Add tap gesture recognizer for clickable username in creator label
        let creatorTapGesture = UITapGestureRecognizer(target: self, action: #selector(creatorLabelTapped(_:)))
        creatorLabel.addGestureRecognizer(creatorTapGesture)

        // Merged social-proof row: "Added by X · saved by N people".
        // The creator name (creatorLabel) opens the profile; the facepile,
        // chevron, or row background opens the savers list.
        infoContainerView.addSubview(savedByView)
        savedByView.addSubview(savedByFacepileView)
        savedByView.addSubview(creatorLabel)
        savedByView.addSubview(savedByChevron)
        let savedByTapGesture = UITapGestureRecognizer(target: self, action: #selector(showSaversList))
        savedByView.addGestureRecognizer(savedByTapGesture)

        infoContainerView.addSubview(practicalButtonsStackView)
        infoContainerView.addSubview(addressLabel)
        infoContainerView.addSubview(hoursLabel)
        infoContainerView.addSubview(mapView)
        infoContainerView.addSubview(venueRewardsView)
        venueRewardsView.delegate = self
        infoContainerView.addSubview(partnerActionsRowView)
        partnerActionsRowView.translatesAutoresizingMaskIntoConstraints = false
        partnerActionsRowView.delegate = self

        // Always add notes labels - visibility will be controlled in configureUI
        infoContainerView.addSubview(notesTitleLabel)
        infoContainerView.addSubview(notesButtonsStackView)
        notesButtonsStackView.addArrangedSubview(notesEditButton)
        notesButtonsStackView.addArrangedSubview(addNotesButton)
        infoContainerView.addSubview(notesLabel)
        
        // Add photos section if user can edit
        let canEdit = place.isAddedByCurrentUser || isHomeOrWorkPlace
        if canEdit {
            infoContainerView.addSubview(photosTitleLabel)
            infoContainerView.addSubview(photosButtonsStackView)
            photosButtonsStackView.addArrangedSubview(photosEditButton)
            photosButtonsStackView.addArrangedSubview(addPhotoButton)
        }
        
        if let tags = place.tags, !tags.isEmpty {
            infoContainerView.addSubview(tagsTitleLabel)
            infoContainerView.addSubview(tagsStackView)
        }
        
        // Quick actions row: Check In / Directions / Call / Website. Edit and
        // Report live in the ••• menu; titles scale slightly to keep four
        // chips untruncated.
        practicalButtonsStackView.addArrangedSubview(checkInRowButton)
        checkInRowButton.addTarget(self, action: #selector(checkInRowButtonTapped), for: .touchUpInside)
        practicalButtonsStackView.addArrangedSubview(directionsRowButton)
        directionsRowButton.addTarget(self, action: #selector(directionsButtonTapped), for: .touchUpInside)

        if effectivePhone != nil {
            practicalButtonsStackView.addArrangedSubview(phoneButton)
            phoneButton.addTarget(self, action: #selector(phoneButtonTapped), for: .touchUpInside)
        }

        if effectiveWebsite != nil {
            practicalButtonsStackView.addArrangedSubview(websiteButton)
            websiteButton.addTarget(self, action: #selector(websiteButtonTapped), for: .touchUpInside)
        }

        // Add action buttons container before circle info. The send-arrow mirrors
        // the nav-bar share button so sharing is reachable inline too.
        infoContainerView.addSubview(actionButtonsContainer)
        actionButtonsContainer.addSubview(likeButton)
        actionButtonsContainer.addSubview(likeCountLabel)
        actionButtonsContainer.addSubview(commentButton)
        actionButtonsContainer.addSubview(commentCountLabel)
        actionButtonsContainer.addSubview(sendButton)
        actionButtonsContainer.addSubview(addToCircleButton)
        actionButtonsContainer.addSubview(followButton)

        // Add comments section
        infoContainerView.addSubview(commentsSection)
        commentsSection.addSubview(commentsSectionTitle)
        commentsSection.addSubview(viewAllCommentsButton)
        commentsSection.addSubview(commentsStackView)

        // Add targets for action buttons
        likeButton.addTarget(self, action: #selector(likeButtonTapped), for: .touchUpInside)
        followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
        commentButton.addTarget(self, action: #selector(commentButtonTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
        viewAllCommentsButton.addTarget(self, action: #selector(commentButtonTapped), for: .touchUpInside)
        
        // Add tap gesture to like count label to show likes list
        let likeCountTapGesture = UITapGestureRecognizer(target: self, action: #selector(showLikesList))
        likeCountLabel.addGestureRecognizer(likeCountTapGesture)
        
        // Add circle info
        infoContainerView.addSubview(circleInfoView)
        circleInfoView.addSubview(circleNameLabel)
        circleInfoView.addSubview(circleButton)
        circleButton.addTarget(self, action: #selector(circleButtonTapped), for: .touchUpInside)
        
        // Add target for update info button
        // updateInfoButton.addTarget(self, action: #selector(updateInfoButtonTapped), for: .touchUpInside) // Commented - automatic migration
        
        // Add target for edit image button
        editImageButton.addTarget(self, action: #selector(editImageButtonTapped(_:)), for: .touchUpInside)
        
        // Add target for notes edit button
        notesEditButton.addTarget(self, action: #selector(notesEditButtonTapped), for: .touchUpInside)
        
        // Add target for add notes button
        addNotesButton.addTarget(self, action: #selector(addNotesButtonTapped), for: .touchUpInside)
        
        // Add target for photo buttons
        photosEditButton.addTarget(self, action: #selector(editImageButtonTapped(_:)), for: .touchUpInside)
        addPhotoButton.addTarget(self, action: #selector(editImageButtonTapped(_:)), for: .touchUpInside)
        
        ratingView.addSubview(ratingImageView)
        ratingView.addSubview(ratingLabel)
        
        // Add tap gesture to rating view for Google reviews
        let ratingTapGesture = UITapGestureRecognizer(target: self, action: #selector(ratingViewTapped))
        ratingView.addGestureRecognizer(ratingTapGesture)
        
        // Add navigation bar buttons — everything else lives in the ••• menu
        let moreButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(moreButtonTapped))
        // Check-in at the top of every place view (same icon everywhere)
        let checkInBarButton = UIBarButtonItem(
            image: .checkInIcon,
            style: .plain,
            target: self,
            action: #selector(checkInRowButtonTapped)
        )
        checkInBarButton.accessibilityLabel = "Check in"
        // share lives in the nav bar (rightBarButtonItem above)
        navigationItem.rightBarButtonItems = [moreButton, navigationItem.rightBarButtonItem!, checkInBarButton]
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Name label — leads the page, above the photo
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.medium),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: categoryLabel.leadingAnchor, constant: -Constants.Spacing.small),

            // Category label
            categoryLabel.topAnchor.constraint(equalTo: nameLabel.topAnchor),
            categoryLabel.trailingAnchor.constraint(equalTo: categoryEditButton.leadingAnchor, constant: -Constants.Spacing.small),
            categoryLabel.heightAnchor.constraint(equalToConstant: 24),

            // Category edit button
            categoryEditButton.topAnchor.constraint(equalTo: nameLabel.topAnchor),
            categoryEditButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            categoryEditButton.widthAnchor.constraint(equalToConstant: 24),
            categoryEditButton.heightAnchor.constraint(equalToConstant: 24),

            // Image view — hangs below the name row
            mediaCarouselView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.medium),
            mediaCarouselView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mediaCarouselView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mediaCarouselView.heightAnchor.constraint(equalToConstant: 300),
            
            // Edit Image button - positioned within imageView
            editImageButton.bottomAnchor.constraint(equalTo: mediaCarouselView.bottomAnchor, constant: -16),
            editImageButton.trailingAnchor.constraint(equalTo: mediaCarouselView.trailingAnchor, constant: -16),
            editImageButton.heightAnchor.constraint(equalToConstant: 32),
            editImageButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            
            // Update Info button - commented out as automatic migration handles this
            // updateInfoButton.bottomAnchor.constraint(equalTo: mediaCarouselView.bottomAnchor, constant: -16),
            // updateInfoButton.trailingAnchor.constraint(equalTo: editImageButton.leadingAnchor, constant: -8),
            // updateInfoButton.heightAnchor.constraint(equalToConstant: 32),
            // updateInfoButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            
            
            // Info container view - positioned below the image with padding
            infoContainerView.topAnchor.constraint(equalTo: mediaCarouselView.bottomAnchor, constant: Constants.Spacing.medium),
            infoContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            infoContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            infoContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Rating view - under the social action row, hidden if no rating
            ratingView.topAnchor.constraint(equalTo: actionButtonsContainer.bottomAnchor, constant: Constants.Spacing.small),
            ratingView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            ratingView.heightAnchor.constraint(equalToConstant: 26),

            // Rating image view
            ratingImageView.leadingAnchor.constraint(equalTo: ratingView.leadingAnchor, constant: Constants.Spacing.small),
            ratingImageView.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor),
            ratingImageView.widthAnchor.constraint(equalToConstant: 18),
            ratingImageView.heightAnchor.constraint(equalToConstant: 18),

            // Rating label
            ratingLabel.leadingAnchor.constraint(equalTo: ratingImageView.trailingAnchor, constant: Constants.Spacing.small),
            ratingLabel.trailingAnchor.constraint(equalTo: ratingView.trailingAnchor, constant: -Constants.Spacing.small),
            ratingLabel.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor),

            // Address label - one-liner under the rating
            addressLabel.topAnchor.constraint(equalTo: ratingView.bottomAnchor, constant: Constants.Spacing.small),
            addressLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            addressLabel.trailingAnchor.constraint(lessThanOrEqualTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),

            // Merged social-proof row directly under the address:
            // facepile + "Added by X · saved by N people" + chevron
            savedByView.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: Constants.Spacing.medium),
            savedByView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            savedByView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),

            savedByFacepileView.leadingAnchor.constraint(equalTo: savedByView.leadingAnchor, constant: Constants.Spacing.small),
            savedByFacepileView.centerYAnchor.constraint(equalTo: savedByView.centerYAnchor),

            creatorLabel.leadingAnchor.constraint(equalTo: savedByFacepileView.trailingAnchor, constant: Constants.Spacing.small),
            creatorLabel.centerYAnchor.constraint(equalTo: savedByView.centerYAnchor),
            creatorLabel.trailingAnchor.constraint(lessThanOrEqualTo: savedByChevron.leadingAnchor, constant: -Constants.Spacing.small),

            savedByChevron.trailingAnchor.constraint(equalTo: savedByView.trailingAnchor, constant: -Constants.Spacing.small),
            savedByChevron.centerYAnchor.constraint(equalTo: savedByView.centerYAnchor),
            savedByChevron.widthAnchor.constraint(equalToConstant: 14),
            savedByChevron.heightAnchor.constraint(equalToConstant: 14),

            // Action buttons container — leads the info card, directly below
            // the photo (heart/comment + Add to My Circle/Follow)
            actionButtonsContainer.topAnchor.constraint(equalTo: infoContainerView.topAnchor, constant: Constants.Spacing.small),
            actionButtonsContainer.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor),
            actionButtonsContainer.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor),
            actionButtonsContainer.heightAnchor.constraint(equalToConstant: 44),
            
            // Like button and count
            likeButton.leadingAnchor.constraint(equalTo: actionButtonsContainer.leadingAnchor, constant: Constants.Spacing.medium),
            likeButton.centerYAnchor.constraint(equalTo: actionButtonsContainer.centerYAnchor),
            likeButton.widthAnchor.constraint(equalToConstant: 30),
            likeButton.heightAnchor.constraint(equalToConstant: 30),
            
            likeCountLabel.leadingAnchor.constraint(equalTo: likeButton.trailingAnchor, constant: 4),
            likeCountLabel.centerYAnchor.constraint(equalTo: actionButtonsContainer.centerYAnchor),
            
            // Comment button and count
            commentButton.leadingAnchor.constraint(equalTo: likeCountLabel.trailingAnchor, constant: Constants.Spacing.medium),
            commentButton.centerYAnchor.constraint(equalTo: actionButtonsContainer.centerYAnchor),
            commentButton.widthAnchor.constraint(equalToConstant: 30),
            commentButton.heightAnchor.constraint(equalToConstant: 30),
            
            commentCountLabel.leadingAnchor.constraint(equalTo: commentButton.trailingAnchor, constant: 4),
            commentCountLabel.centerYAnchor.constraint(equalTo: actionButtonsContainer.centerYAnchor),

            // Send-arrow (share) sits inline after the comment count
            sendButton.leadingAnchor.constraint(equalTo: commentCountLabel.trailingAnchor, constant: Constants.Spacing.medium),
            sendButton.centerYAnchor.constraint(equalTo: actionButtonsContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
            sendButton.heightAnchor.constraint(equalToConstant: 30),

            followButton.trailingAnchor.constraint(equalTo: actionButtonsContainer.trailingAnchor, constant: -Constants.Spacing.medium),
            followButton.centerYAnchor.constraint(equalTo: actionButtonsContainer.centerYAnchor),

            // Add to Circle sits left of Follow, same size (sibling actions)
            addToCircleButton.trailingAnchor.constraint(equalTo: followButton.leadingAnchor, constant: -Constants.Spacing.small),
            addToCircleButton.centerYAnchor.constraint(equalTo: actionButtonsContainer.centerYAnchor),
            addToCircleButton.leadingAnchor.constraint(greaterThanOrEqualTo: sendButton.trailingAnchor, constant: Constants.Spacing.small),

            // Practical actions row — after the social-proof row
            practicalButtonsStackView.topAnchor.constraint(equalTo: savedByView.bottomAnchor, constant: Constants.Spacing.medium),
            practicalButtonsStackView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            practicalButtonsStackView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            practicalButtonsStackView.heightAnchor.constraint(equalToConstant: 44),

            // About card (description + hours); collapses via the stored
            // top/height constraints below when there's nothing to show
            aboutCardView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            aboutCardView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),

            aboutStackView.topAnchor.constraint(equalTo: aboutCardView.topAnchor, constant: Constants.Spacing.small),
            aboutStackView.leadingAnchor.constraint(equalTo: aboutCardView.leadingAnchor, constant: Constants.Spacing.medium),
            aboutStackView.trailingAnchor.constraint(equalTo: aboutCardView.trailingAnchor, constant: -Constants.Spacing.medium),

            // Map view - tap opens directions
            mapView.topAnchor.constraint(equalTo: aboutCardView.bottomAnchor, constant: Constants.Spacing.medium),
            mapView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            mapView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            mapView.heightAnchor.constraint(equalToConstant: 160)
        ])

        // Partner action chips dock under the practical row; collapsed
        // (height 0, zero gap) until the catalog yields eligible groups, so
        // the layout is pixel-identical to pre-feature when the row is empty
        NSLayoutConstraint.activate([
            partnerActionsRowView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            partnerActionsRowView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium)
        ])
        let partnerTop = partnerActionsRowView.topAnchor.constraint(equalTo: practicalButtonsStackView.bottomAnchor, constant: 0)
        let partnerHeight = partnerActionsRowView.heightAnchor.constraint(equalToConstant: 0)
        partnerTop.isActive = true
        partnerHeight.isActive = true
        partnerActionsTopConstraint = partnerTop
        partnerActionsHeightConstraint = partnerHeight

        // About card collapses (top gap + height) when it has no content;
        // when visible, the height follows the stack's bottom instead
        let aboutTop = aboutCardView.topAnchor.constraint(equalTo: partnerActionsRowView.bottomAnchor, constant: Constants.Spacing.medium)
        let aboutBottom = aboutStackView.bottomAnchor.constraint(equalTo: aboutCardView.bottomAnchor, constant: -Constants.Spacing.small)
        aboutBottom.priority = .defaultHigh
        let aboutHeight = aboutCardView.heightAnchor.constraint(equalToConstant: 0)
        aboutHeight.isActive = false
        NSLayoutConstraint.activate([aboutTop, aboutBottom])
        aboutTopConstraint = aboutTop
        aboutHeightConstraint = aboutHeight

        // Social-proof row is always visible — it carries "Added by" from the
        // start; the saver count and facepile fill in once savers load
        let savedByHeight = savedByView.heightAnchor.constraint(equalToConstant: 40)
        savedByHeight.isActive = true
        savedByHeightConstraint = savedByHeight

        // Venue rewards section sits between the map and the notes; collapsed
        // (zero height, zero top gap) until a venue is found, mirroring the
        // savedByView pattern above
        let venueTop = venueRewardsView.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: 0)
        let venueHeight = venueRewardsView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            venueTop,
            venueRewardsView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            venueRewardsView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            venueHeight
        ])
        venueRewardsTopConstraint = venueTop
        venueRewardsHeightConstraint = venueHeight

        // Dynamic constraints based on available data
        var lastAnchor: NSLayoutYAxisAnchor = venueRewardsView.bottomAnchor
        var additionalSpacing: CGFloat = Constants.Spacing.medium

        // Always set up notes constraints - visibility controlled in configureUI
        NSLayoutConstraint.activate([
            notesTitleLabel.topAnchor.constraint(equalTo: lastAnchor, constant: additionalSpacing),
            notesTitleLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            
            notesButtonsStackView.centerYAnchor.constraint(equalTo: notesTitleLabel.centerYAnchor),
            notesButtonsStackView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            notesLabel.topAnchor.constraint(equalTo: notesTitleLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            notesLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            notesLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium)
        ])
        
        lastAnchor = notesLabel.bottomAnchor
        
        // Add photos section constraints if user can edit
        if canEdit {
            NSLayoutConstraint.activate([
                photosTitleLabel.topAnchor.constraint(equalTo: lastAnchor, constant: additionalSpacing),
                photosTitleLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
                
                photosButtonsStackView.centerYAnchor.constraint(equalTo: photosTitleLabel.centerYAnchor),
                photosButtonsStackView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium)
            ])
            
            lastAnchor = photosTitleLabel.bottomAnchor
        }
        
        // Add tags if available
        if let tags = place.tags, !tags.isEmpty {
            NSLayoutConstraint.activate([
                tagsTitleLabel.topAnchor.constraint(equalTo: lastAnchor, constant: additionalSpacing),
                tagsTitleLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
                
                tagsStackView.topAnchor.constraint(equalTo: tagsTitleLabel.bottomAnchor, constant: Constants.Spacing.tiny),
                tagsStackView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
                tagsStackView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium)
            ])
            
            lastAnchor = tagsStackView.bottomAnchor
        }
        
        // Add comments section constraints
        NSLayoutConstraint.activate([
            commentsSection.topAnchor.constraint(equalTo: lastAnchor, constant: Constants.Spacing.large),
            commentsSection.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            commentsSection.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            commentsSectionTitle.topAnchor.constraint(equalTo: commentsSection.topAnchor, constant: Constants.Spacing.medium),
            commentsSectionTitle.leadingAnchor.constraint(equalTo: commentsSection.leadingAnchor, constant: Constants.Spacing.medium),
            
            viewAllCommentsButton.centerYAnchor.constraint(equalTo: commentsSectionTitle.centerYAnchor),
            viewAllCommentsButton.trailingAnchor.constraint(equalTo: commentsSection.trailingAnchor, constant: -Constants.Spacing.medium),
            
            commentsStackView.topAnchor.constraint(equalTo: commentsSectionTitle.bottomAnchor, constant: Constants.Spacing.small),
            commentsStackView.leadingAnchor.constraint(equalTo: commentsSection.leadingAnchor, constant: Constants.Spacing.medium),
            commentsStackView.trailingAnchor.constraint(equalTo: commentsSection.trailingAnchor, constant: -Constants.Spacing.medium),
            commentsStackView.bottomAnchor.constraint(equalTo: commentsSection.bottomAnchor, constant: -Constants.Spacing.medium)
        ])
        
        // Update lastAnchor to point to comments section
        lastAnchor = commentsSection.bottomAnchor
        
        // Add circle info only if we have a circle or circleId
        if circle != nil || (place.circleId != nil && !place.circleId!.isEmpty) {
            NSLayoutConstraint.activate([
                circleInfoView.topAnchor.constraint(equalTo: lastAnchor, constant: Constants.Spacing.large),
                circleInfoView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
                circleInfoView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
                circleInfoView.heightAnchor.constraint(equalToConstant: 50),
                
                circleNameLabel.leadingAnchor.constraint(equalTo: circleInfoView.leadingAnchor, constant: Constants.Spacing.medium),
                circleNameLabel.centerYAnchor.constraint(equalTo: circleInfoView.centerYAnchor),
                
                circleButton.trailingAnchor.constraint(equalTo: circleInfoView.trailingAnchor, constant: -Constants.Spacing.medium),
                circleButton.centerYAnchor.constraint(equalTo: circleInfoView.centerYAnchor),
                
                circleInfoView.bottomAnchor.constraint(equalTo: infoContainerView.bottomAnchor, constant: -Constants.Spacing.medium)
            ])
        } else {
            // No circle info, just add bottom constraint
            lastAnchor.constraint(equalTo: infoContainerView.bottomAnchor, constant: -Constants.Spacing.medium).isActive = true
        }
        
        // Ensure all buttons on imageView are interactive
        mediaCarouselView.bringSubviewToFront(editImageButton)
        // mediaCarouselView.bringSubviewToFront(updateInfoButton) // Commented - automatic migration
        
        // Set up button actions
        categoryEditButton.addTarget(self, action: #selector(editButtonTapped), for: .touchUpInside)
    }
    
    private func configureUI() {
        // Set place details
        nameLabel.text = place.name
        
        // Creator info
        configureCreatorInfo()
        
        // Add to Circle button
        configureAddToCircleButton()
        
        // Category - "Other" is noise, so hide the chip for it
        if place.displayCategory == "Other" {
            categoryLabel.text = ""
            categoryLabel.isHidden = true
        } else {
            categoryLabel.text = "  \(place.displayCategory)  " // Add padding with spaces
            categoryLabel.isHidden = false
        }

        // Set category color using centralized property
        categoryLabel.backgroundColor = place.category.color
        
        // Set default image - this will be called before street view loads
        configureDefaultImage()
        
        // Update edit button visibility based on whether user can edit this place
        let canEdit = place.isAddedByCurrentUser || isHomeOrWorkPlace
        // Anyone who can view the place can contribute photos — they're stored
        // in the shared Global Place system with "Photo by [name]" attribution,
        // and users can only delete their own. Owner-only actions (Street View
        // image, Remove Photo) are gated inside the action sheet instead.
        editImageButton.isHidden = false
        categoryEditButton.isHidden = !canEdit
        
        // Update photo section buttons visibility
        if canEdit {
            // Check if place has custom photos
            let hasCustomPhoto = (place.photos?.count ?? 0) > 0 || customImage != nil
            
            if hasCustomPhoto {
                addPhotoButton.isHidden = true
                photosEditButton.isHidden = false
            } else {
                addPhotoButton.isHidden = false
                photosEditButton.isHidden = true
            }
            
            photosTitleLabel.isHidden = false
        } else {
            photosTitleLabel.isHidden = true
            photosButtonsStackView.isHidden = true
        }
        
        
        // Show update info button for places showing default category image that can be enriched with Google data
        // (no custom image, no API photos, and no street view)
        let hasCustomImage = customImage != nil || isHomeOrWorkPlace
        let hasAPIPhotos = (place.photos?.count ?? 0) > 0
        let isShowingDefaultIcon = !hasCustomImage && !hasAPIPhotos && !showingStreetView
        
        // Show button if showing default icon AND either has googlePlaceId OR has location coordinates
        let canSearchGooglePlaces = place.googlePlaceId != nil || place.location != nil
        // updateInfoButton.isHidden = !isShowingDefaultIcon || !canSearchGooglePlaces // Commented - automatic migration
        
        // Description - only show if available
        Logger.debug("🔍 [PlaceDetailViewController] Place ID: \(place.id)")
        Logger.debug("🔍 [PlaceDetailViewController] Place description: \(place.description ?? "nil")")
        Logger.debug("🔍 [PlaceDetailViewController] Place reviews count: \(place.reviews?.count ?? 0)")
        Logger.debug("🔍 [PlaceDetailViewController] Place likes count: \(place.likesCount ?? 0)")
        Logger.debug("🔍 [PlaceDetailViewController] Place comments count: \(place.commentsCount ?? 0)")
        
        // Phone/website already have their own chips — drop the duplicated
        // "Phone: …" / "Website: …" lines from the description text
        var aboutText = place.description ?? ""
        if effectivePhone != nil || effectiveWebsite != nil {
            aboutText = aboutText
                .components(separatedBy: "\n")
                .filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if effectivePhone != nil && trimmed.hasPrefix("Phone:") { return false }
                    if effectiveWebsite != nil && trimmed.hasPrefix("Website:") { return false }
                    return true
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !aboutText.isEmpty {
            descriptionLabel.attributedText = createAttributedDescription(from: aboutText)
            descriptionLabel.isHidden = false
        } else {
            descriptionLabel.isHidden = true
        }

        // The saver's personal 0–10 score, when they gave one
        if let userRating = place.userRating {
            let who = place.isAddedByCurrentUser ? "Your" : "\(place.addedByDisplayName)'s"
            userRatingLabel.text = "★ \(who) rating: \(userRating)/10"
            userRatingLabel.isHidden = false
        } else {
            userRatingLabel.isHidden = true
        }

        // Rating - one meta line: rating (count) · price
        if let rating = place.rating, rating > 0 {
            var ratingText = String(format: "%.1f", rating)
            if let userRatingsTotal = place.userRatingsTotal, userRatingsTotal > 0 {
                ratingText += " (\(userRatingsTotal))"
            }

            if let priceLevel = place.priceLevel {
                ratingText += " · " + String(repeating: "$", count: priceLevel.rawValue + 1)
            }

            // Add external link indicator if Google Place ID exists
            if place.googlePlaceId != nil {
                ratingText += " ↗"
            }

            ratingLabel.text = ratingText
            ratingView.isHidden = false

            // Add subtle highlight on tap capability
            ratingView.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
        } else {
            // Hide rating view when no rating is available
            ratingView.isHidden = true
        }
        
        // Address
        addressLabel.text = place.address
        
        // The only note a place carries is the saver's private one. Anything
        // written for other people is a comment on the venue (see the comments
        // section below), so nothing here is ever shown to another user.
        // When viewing someone else's copy of a venue we also saved, our note
        // comes from our own save record (mySaveOfVenue).
        var notesText = ""
        if place.isAddedByCurrentUser, let privateNotes = place.privateNotes, !privateNotes.isEmpty {
            notesText = privateNotes
        } else if let myNotes = mySaveOfVenue?.privateNotes, !myNotes.isEmpty {
            notesText = myNotes
        }

        if !notesText.isEmpty {
            notesLabel.text = notesText
            notesLabel.isHidden = false
            addNotesButton.isHidden = true
            notesEditButton.isHidden = false
        } else {
            notesLabel.isHidden = true
            addNotesButton.isHidden = false
            notesEditButton.isHidden = true
        }
        
        // Always show notes section
        notesTitleLabel.isHidden = false
        
        // Make notes tappable when they exist
        notesLabel.isUserInteractionEnabled = true
        let notesTapGesture = UITapGestureRecognizer(target: self, action: #selector(notesLabelTapped))
        notesLabel.addGestureRecognizer(notesTapGesture)
        
        // Tags
        if let tags = place.tags, !tags.isEmpty {
            setupTagsView(tags: tags)
        }
        
        // Price Level
        if let priceLevel = place.priceLevel {
            let priceString = String(repeating: "$", count: priceLevel.rawValue + 1)
            // Could add a price level label here if UI element exists
        }
        
        
        // Description constraint is already set in setupUI
        
        // Opening Hours (inside the About card)
        if let openingHours = place.openingHours, !openingHours.isEmpty {
            hoursLabel.text = formatOpeningHours(openingHours)
            hoursLabel.isHidden = false
        } else {
            hoursLabel.isHidden = true
        }

        updateAboutCardVisibility()
        
        // Circle info
        updateCircleInfo()
        
        // Update likes and comments UI
        updateLikeButton()
        syncFollowState(from: place)
        
        // Update comment count immediately from place data
        updateCommentCount(place.commentsCount ?? 0)
        
        // Fetch full comments for inline display
        fetchCommentCount()
        
        // Load place photos if available
        loadPlacePhotos()
        
        // After loading photos, check if we need to show street view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let hasPhotos = !self.placePhotos.isEmpty || self.customImage != nil || (self.place.photos != nil && !self.place.photos!.isEmpty)
            if !hasPhotos && self.streetViewImage != nil {
                // No photos loaded, but we have street view - show it
                self.showingStreetView = true
                self.updateImageView()
                self.streetViewToggleButton.isHidden = true
            }
        }
        
    }
    
    private func updateCircleInfo() {
        if let circle = self.circle {
            circleNameLabel.text = "In: \(circle.name)"
        } else if place.circleId != nil && !place.circleId!.isEmpty {
            circleNameLabel.text = "Loading circle..."
        } else {
            // Hide circle info view for places without circles (e.g., Home/Work)
            circleInfoView.isHidden = true
        }
    }
    
    private func setupTagsView(tags: [String]) {
        // Clear stack view first
        tagsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Add tags
        for tag in tags {
            let tagView = UIView()
            tagView.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.5)
            tagView.layer.cornerRadius = 8
            
            let tagLabel = UILabel()
            tagLabel.text = "#\(tag)"
            tagLabel.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
            tagLabel.textColor = Constants.Colors.primary
            tagLabel.translatesAutoresizingMaskIntoConstraints = false
            
            tagView.addSubview(tagLabel)
            
            NSLayoutConstraint.activate([
                tagLabel.topAnchor.constraint(equalTo: tagView.topAnchor, constant: Constants.Spacing.tiny),
                tagLabel.leadingAnchor.constraint(equalTo: tagView.leadingAnchor, constant: Constants.Spacing.small),
                tagLabel.trailingAnchor.constraint(equalTo: tagView.trailingAnchor, constant: -Constants.Spacing.small),
                tagLabel.bottomAnchor.constraint(equalTo: tagView.bottomAnchor, constant: -Constants.Spacing.tiny)
            ])
            
            tagsStackView.addArrangedSubview(tagView)
        }
    }
    
    private func formatOpeningHours(_ hours: [OpeningHour]) -> String {
        OpeningHoursFormatter.todaySummary(hours)
    }
    
    private func setupMap() {
        // Add annotation for the place location
        if let location = place.location?.clLocation {
            // Create annotation
            let annotation = MKPointAnnotation()
            annotation.coordinate = location.coordinate
            annotation.title = place.name
            annotation.subtitle = place.displayCategory
            mapView.addAnnotation(annotation)
            
            // Set map region
            let region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: false)
            
            // Select the annotation to show callout
            mapView.selectAnnotation(annotation, animated: false)

            // Tapping the map opens directions (replaces the old Navigate button)
            let mapTapGesture = UITapGestureRecognizer(target: self, action: #selector(directionsButtonTapped))
            mapView.addGestureRecognizer(mapTapGesture)
        }
    }
    
    // MARK: - Configuration Helpers
    
    private func configureCreatorInfo() {
        let attributedString = NSMutableAttributedString()
        
        // Determine creator info and whether it should be clickable
        let currentUserId = AuthService.shared.getUserId() ?? ""
        var isClickable = false
        
        if let addedByUser = place.addedByUser {
            // We have user details, make it clickable
            creatorUser = addedByUser
            isClickable = true
            
            let addedByText = NSAttributedString(string: "Added by ", attributes: [
                .font: UIFont.systemFont(ofSize: Constants.FontSize.small),
                .foregroundColor: Constants.Colors.secondaryLabel
            ])
            attributedString.append(addedByText)
            
            let nameText = NSAttributedString(string: addedByUser.displayName, attributes: [
                .font: UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .medium),
                .foregroundColor: Constants.Colors.primary,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ])
            attributedString.append(nameText)
        } else if place.addedBy == currentUserId {
            // Current user, not clickable
            let text = NSAttributedString(string: "Added by you", attributes: [
                .font: UIFont.systemFont(ofSize: Constants.FontSize.small),
                .foregroundColor: Constants.Colors.secondaryLabel
            ])
            attributedString.append(text)
        } else if let circle = circle {
            if circle.owner == place.addedBy {
                if let ownerDetails = circle.ownerDetails {
                    // Circle owner with details, make it clickable
                    creatorUser = ownerDetails
                    isClickable = true
                    
                    let addedByText = NSAttributedString(string: "Added by ", attributes: [
                        .font: UIFont.systemFont(ofSize: Constants.FontSize.small),
                        .foregroundColor: Constants.Colors.secondaryLabel
                    ])
                    attributedString.append(addedByText)
                    
                    let nameText = NSAttributedString(string: ownerDetails.displayName, attributes: [
                        .font: UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .medium),
                        .foregroundColor: Constants.Colors.primary,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ])
                    attributedString.append(nameText)
                } else {
                    // No owner details
                    let text = NSAttributedString(string: "Added by circle owner", attributes: [
                        .font: UIFont.systemFont(ofSize: Constants.FontSize.small),
                        .foregroundColor: Constants.Colors.secondaryLabel
                    ])
                    attributedString.append(text)
                }
            } else {
                // Member without details
                let text = NSAttributedString(string: "Added by a member", attributes: [
                    .font: UIFont.systemFont(ofSize: Constants.FontSize.small),
                    .foregroundColor: Constants.Colors.secondaryLabel
                ])
                attributedString.append(text)
            }
        } else {
            // Connection without details
            let text = NSAttributedString(string: "Added by a connection", attributes: [
                .font: UIFont.systemFont(ofSize: Constants.FontSize.small),
                .foregroundColor: Constants.Colors.secondaryLabel
            ])
            attributedString.append(text)
        }
        
        // Origin flag for imported saves: "Added by you · Google import" —
        // tells you whether this pin came from an import or an in-app add
        if let origin = place.importOriginLabel {
            let originText = NSAttributedString(string: " · \(origin)", attributes: [
                .font: UIFont.italicSystemFont(ofSize: Constants.FontSize.small),
                .foregroundColor: Constants.Colors.secondaryLabel
            ])
            attributedString.append(originText)
        }

        // Merge the saver count into the same row: "Added by X · saved by N people"
        if savedByCount > 1 {
            let saverText = NSAttributedString(string: " · saved by \(savedByCount) people", attributes: [
                .font: UIFont.systemFont(ofSize: Constants.FontSize.small),
                .foregroundColor: Constants.Colors.secondaryLabel
            ])
            attributedString.append(saverText)
        }

        creatorLabel.attributedText = attributedString
        
        // Update cursor if clickable
        if isClickable {
            creatorLabel.isUserInteractionEnabled = true
        } else {
            creatorLabel.isUserInteractionEnabled = false
        }
    }
    
    private func configureAddToCircleButton() {
        // Check if the current user already has this place in any of their circles
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // Hide button if:
        // 1. User created this place themselves
        // 2. Place is already in one of user's circles
        // 3. User doesn't have any circles to add to
        
        if AddToCircleGate.isOwnSave(place, currentUserId: currentUserId) {
            // User created this place
            setAddToCircleVisible(false)
            return
        }
        
        // Check if user already has this place. Matching by save-doc id is
        // not enough: arriving from the activity feed, this screen holds
        // ANOTHER user's copy (different doc id) of a venue the current user
        // may also have saved — compare by venue identity instead.
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                switch result {
                case .success(let userCircles):
                    // No circles to add to, or a circle already holds this doc
                    guard case .checkVenueMatch(let circleIds) = AddToCircleGate.verdict(for: self.place, in: userCircles) else {
                        self.setAddToCircleVisible(false)
                        return
                    }

                    PlaceService.shared.fetchPlacesByMultipleCircles(circleIds: circleIds) { [weak self] placesResult in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            switch placesResult {
                            case .success(let myPlaces):
                                if AddToCircleGate.verdictAfterVenueCheck(for: self.place, myPlaces: myPlaces) == .hide {
                                    self.setAddToCircleVisible(false)
                                } else {
                                    self.setAddToCircleVisible(true)
                                    self.addToCircleButton.addTarget(self, action: #selector(self.addToCircleButtonTapped), for: .touchUpInside)
                                }
                            case .failure:
                                // Can't verify — keep the button so adding stays
                                // possible (the add flow has its own duplicate check)
                                self.setAddToCircleVisible(true)
                                self.addToCircleButton.addTarget(self, action: #selector(self.addToCircleButtonTapped), for: .touchUpInside)
                            }
                        }
                    }

                case .failure:
                    self.setAddToCircleVisible(false)
                }
            }
        }
    }

    private func updateAddressTitleConstraint() {
        // No need to update constraints dynamically anymore
        // The constraint is set in setupUI to always anchor to addToCircleButton
    }
    
    private func loadUserCircles() {
        CircleService.shared.fetchUserCircles { [weak self] result in
            switch result {
            case .success(let circles):
                self?.userCircles = circles
            case .failure(let error):
                Logger.debug("Failed to load user circles: \(error)")
                // Continue without user circles - will treat as check-in
                self?.userCircles = []
            }
        }
    }
    
    /// The place handed in by the parent list can be stale — refetch it so
    /// photos (and other fields) added since the list loaded are reflected.
    private func refreshPlaceFromServer() {
        guard !isHomeOrWorkPlace else { return }

        PlaceService.shared.fetchPlaceById(id: place.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, case .success(let updatedPlace) = result else { return }
                self.place = updatedPlace
                // Full re-render: the About card (description/hours/rating)
                // was drawn from the stale list copy — venue enrichment that
                // landed since (e.g. a share-extension save) must show without
                // reopening the screen. updateMediaCarousel() runs after so
                // configureDefaultImage() can't clobber loaded photos.
                self.configureUI()
                self.updateMediaCarousel()
                // Likes/comments are global per place, so the server-refreshed
                // copy can carry social state the stale list copy didn't have
                self.updateLikeButton()
                self.syncFollowState(from: updatedPlace)
                self.updateCommentCount(updatedPlace.commentsCount ?? 0)
                if let photos = updatedPlace.photos, !photos.isEmpty, updatedPlace.isAddedByCurrentUser {
                    self.addPhotoButton.isHidden = true
                    self.photosEditButton.isHidden = false
                }
            }
        }
    }

    // MARK: - Venue rewards (offers + announcements for this place)

    private func loadPartnerActions() {
        venueLoader.loadPartnerActions()
    }

    private func loadVenueRewards() {
        venueLoader.loadVenueRewards()
    }

    private func loadGlobalPlaceData() {
        venueLoader.loadGlobalPlaceData()
    }
    
    // MARK: - Actions
    
    @objc private func addToCircleButtonTapped() {
        // Fetch user's circles to show in picker
        CircleService.shared.fetchUserCircles { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let circles):
                    if circles.isEmpty {
                        // No circles available
                        AlertPresenter.showError(title: "No Circles", message: "You need to create a circle first before adding places to it.", from: self)
                    } else {
                        // Show circle picker in the user's own order (same as the profile grid)
                        let pickerVC = CirclePickerViewController(circles: circles)
                        pickerVC.onCircleSelected = { [weak self] selectedCircle in
                            self?.addPlaceToCircle(selectedCircle)
                        }
                        let navController = UINavigationController(rootViewController: pickerVC)
                        self.present(navController, animated: true)
                    }
                    
                case .failure(let error):
                    self.showError("Failed to load circles: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func creatorLabelTapped(_ gesture: UITapGestureRecognizer) {
        guard let user = creatorUser else { 
            Logger.debug("No creator user data available")
            return 
        }
        
        // Navigate to the user's profile
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func shareButtonTapped() {
        // Create a formatted string with place details
        var shareText = "📍 \(place.name)"

        if let description = place.description, !description.isEmpty {
            shareText += "\n\(description)"
        }

        shareText += "\n\(place.address)"

        if let phone = place.phone {
            shareText += "\n📞 \(phone)"
        }

        if let website = place.website {
            shareText += "\n🌐 \(website)"
        }

        if let rating = place.rating {
            let stars = String(repeating: "⭐", count: Int(rating.rounded()))
            shareText += "\n\(stars) \(rating)/5.0"
        }

        shareText += "\n\nSaved on Circles — see it (and who recommends it) here:"

        // The Circles place link is THE link of the share: with the app
        // installed it opens the place directly (carrying share attribution
        // so the sharer earns points when the recipient adds it); without
        // the app it renders a preview page with an App Store fallback
        let activityItems: [Any] = [shareText, ShareLinks.place(id: place.id)]

        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityViewController, animated: true)
    }
    
    @objc private func checkInRowButtonTapped() {
        CheckInViewController.present(from: self, prefilledPlace: place)
    }

    @objc private func directionsButtonTapped() {
        // Open directions to the place in Maps app
        if let location = place.location?.clLocation {
            // Try Google Maps first
            let googleMapsURL = URL(string: "comgooglemaps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&directionsmode=driving")
            
            if let url = googleMapsURL, UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // Fallback to Apple Maps
                let appleMapsURL = URL(string: "maps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&dirflg=d")
                if let url = appleMapsURL {
                    UIApplication.shared.open(url)
                }
            }
        } else {
            showError("Location information is not available for this place.")
        }
    }
    
    @objc private func ratingViewTapped() {
        // Open Google reviews by searching for the place name and reviews
        // This approach ensures users see reviews prominently
        
        // Build search query with place name and address
        var searchComponents = [place.name]
        
        // Add address if available
        if !place.address.isEmpty {
            searchComponents.append(place.address)
        }
        
        // Add "reviews" to the search to ensure review results show up
        searchComponents.append("reviews")
        
        // Create the search query
        let searchQuery = searchComponents.joined(separator: " ")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Open Google search for reviews
        // This will show the Google knowledge panel with reviews prominently displayed
        let googleSearchURL = URL(string: "https://www.google.com/search?q=\(searchQuery)")
        
        if let url = googleSearchURL {
            UIApplication.shared.open(url)
        } else {
            // Fallback: If URL creation fails somehow, try with just the name
            let fallbackQuery = "\(place.name) reviews".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let fallbackURL = URL(string: "https://www.google.com/search?q=\(fallbackQuery)") {
                UIApplication.shared.open(fallbackURL)
            }
        }
    }
    
    @objc private func websiteButtonTapped() {
        if let websiteString = effectiveWebsite, let url = URL(string: websiteString) {
            UIApplication.shared.open(url)
        }
    }

    @objc private func phoneButtonTapped() {
        if let phoneString = effectivePhone {
            let cleanedPhone = phoneString.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            if let url = URL(string: "tel://\(cleanedPhone)") {
                UIApplication.shared.open(url)
            }
        }
    }
    
    @objc private func circleButtonTapped() {
        if let circle = self.circle {
            let circleDetailVC = CircleDetailViewController(circle: circle)
            navigationController?.pushViewController(circleDetailVC, animated: true)
        } else {
            showError("Circle information is still loading. Please try again in a moment.")
        }
    }
    
    @objc private func moreButtonTapped() {
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = []

        // Edit/move/update-address all operate on the viewer's own save doc —
        // someone else's place isn't editable from here (venue corrections go
        // through the flag flow; owners manage venue data via the storefront)
        // A venue owner is here to run their STORE, not organize a personal
        // save — circle moves and save-level editing don't belong in their menu
        if place.isAddedByCurrentUser && !ownerEdit.isVenueOwner {
            actions.append((title: "Edit Place", style: .default, handler: { [weak self] in
                self?.editButtonTapped()
            }))
            actions.append((title: "Move to Different Circle", style: .default, handler: { [weak self] in
                self?.moveToCircleButtonTapped()
            }))
            if place.location?.clLocation != nil {
                actions.append((title: "Update Address", style: .default, handler: { [weak self] in
                    self?.updateAddressButtonTapped()
                }))
            }
        } else if ownerEdit.isVenueOwner {
            // Verified owner: the page's fields are tap-to-edit directly, so
            // no menu entry needed — their extras append below.
        } else {
            actions.append((title: "Flag Incorrect Info", style: .default, handler: { [weak self] in
                self?.flagPlaceInfoTapped()
            }))
            // Someone else's save: their photos/notes are UGC, so it needs the
            // report/unfollow/block path too (App Review 1.2)
            actions.append((title: "Report Inappropriate Content", style: .destructive, handler: { [weak self] in
                guard let self = self else { return }
                self.presentContentModerationSheet(
                    contentType: "place",
                    contentId: self.place.id,
                    ownerId: self.place.addedBy,
                    ownerName: self.place.addedByUser?.displayName,
                    onContentHidden: { [weak self] in
                        if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                            nav.popViewController(animated: true)
                        } else {
                            self?.dismiss(animated: true)
                        }
                    }
                )
            }))
        }

        if ownerEdit.isVenueOwner {
            actions.append((title: "Set Cover Photo", style: .default, handler: { [weak self] in
                self?.presentCoverPhotoPicker()
            }))
            actions.append((title: ownerEdit.viewingAsCustomer ? "Back to Owner View" : "View as Customer", style: .default, handler: { [weak self] in
                self?.ownerEdit.toggleViewAsCustomer()
            }))
        }

        AlertPresenter.showActionSheet(
            actions: actions,
            from: self,
            sourceView: navigationItem.rightBarButtonItems?.first?.value(forKey: "view") as? UIView
        )
    }
    
    @objc private func editButtonTapped() {
        let editPlaceVC = EditPlaceViewController(place: place)
        editPlaceVC.delegate = self
        let navController = UINavigationController(rootViewController: editPlaceVC)
        present(navController, animated: true)
    }

    @objc private func flagPlaceInfoTapped() {
        promptFlagPlaceInfo(placeId: place.id, placeName: place.name)
    }
    
    @objc private func moveToCircleButtonTapped() {
        let circleSelectionVC = CircleSelectionViewController(
            excludedCircleId: place.circleId ?? "",
            customTitle: "Select Circle to Move Place To"
        )
        circleSelectionVC.delegate = self
        present(circleSelectionVC, animated: true)
    }
    
    @objc private func likeButtonTapped() {
        // Check if place has likes - if so, show likes list instead of toggling
        let likeCount = place.likesCount ?? place.likes?.count ?? 0
        if likeCount > 0 {
            showLikesList()
            return
        }
        
        // If no likes, toggle like as usual
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // Call API to toggle like
        PlaceService.shared.likePlace(id: place.id) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let updatedPlace):
                    // Update local place data
                    self.place = updatedPlace
                    
                    // Update UI
                    self.updateLikeButton()
                    
                    // Show animation
                    UIView.animate(withDuration: 0.1, animations: {
                        self.likeButton.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                    }) { _ in
                        UIView.animate(withDuration: 0.1) {
                            self.likeButton.transform = .identity
                        }
                    }
                    
                case .failure(let error):
                    Logger.error("Failed to toggle like: \(error)")
                    self.showAlert(title: "Error", message: "Failed to update like. Please try again.")
                }
            }
        }
    }
    
    @objc private func followButtonTapped() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()

        // Optimistic toggle; revert on failure
        let wasFollowing = isFollowingPlace
        isFollowingPlace = !wasFollowing
        placeFollowersCount += wasFollowing ? -1 : 1
        updateFollowButton()

        let completion: (Result<PlaceFollowResponse, Error>) -> Void = { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.isFollowingPlace = response.following
                    self.placeFollowersCount = response.followersCount
                    self.updateFollowButton()
                case .failure(let error):
                    Logger.error("Failed to toggle follow: \(error)")
                    self.isFollowingPlace = wasFollowing
                    self.placeFollowersCount += wasFollowing ? 1 : -1
                    self.updateFollowButton()
                    self.showAlert(title: "Error", message: "Failed to update follow. Please try again.")
                }
            }
        }
        if wasFollowing {
            PlaceService.shared.unfollowPlace(id: place.id, completion: completion)
        } else {
            PlaceService.shared.followPlace(id: place.id, completion: completion)
        }
    }

    @objc private func showLikesList() {
        let likeCount = place.likesCount ?? place.likes?.count ?? 0
        if likeCount > 0 {
            let likesVC = PlaceLikesViewController()
            likesVC.placeId = place.id
            likesVC.placeName = place.name
            navigationController?.pushViewController(likesVC, animated: true)
        }
    }

    // MARK: - Saved By

    private func loadPlaceSavers() {
        PlaceService.shared.fetchPlaceSavers(id: place.id) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let response) = result {
                    self?.configureSavedByRow(with: response)
                }
            }
        }
    }

    private func configureSavedByRow(with response: PlaceSaversResponse) {
        // Refresh the merged row text ("Added by X · saved by N people")
        savedByCount = response.totalCount
        configureCreatorInfo()

        // Facepile of up to 3 saver avatars
        savedByFacepileView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for user in response.savers.prefix(3) {
            let avatarView = UIImageView()
            avatarView.contentMode = .scaleAspectFill
            avatarView.clipsToBounds = true
            avatarView.layer.cornerRadius = 12
            avatarView.layer.borderWidth = 1.5
            avatarView.layer.borderColor = Constants.Colors.secondaryBackground.cgColor
            avatarView.backgroundColor = Constants.Colors.tertiaryBackground
            avatarView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                avatarView.widthAnchor.constraint(equalToConstant: 24),
                avatarView.heightAnchor.constraint(equalToConstant: 24)
            ])
            avatarView.image = UIImage(systemName: "person.circle.fill")
            avatarView.tintColor = Constants.Colors.primary
            if let profilePicture = user.profilePicture {
                ImageService.shared.loadImage(from: profilePicture) { [weak avatarView] image in
                    DispatchQueue.main.async {
                        if let image = image {
                            avatarView?.image = image
                        }
                    }
                }
            }
            savedByFacepileView.addArrangedSubview(avatarView)
        }

        savedByView.isHidden = false
        savedByHeightConstraint?.constant = 40
    }

    @objc private func showSaversList() {
        let saversVC = PlaceSaversViewController()
        saversVC.placeId = place.id
        saversVC.placeName = place.name
        navigationController?.pushViewController(saversVC, animated: true)
    }
    
    @objc func commentButtonTapped() {
        // Present comments view controller
        let commentsVC = PlaceCommentsViewController(place: place)
        commentsVC.onCommentsUpdated = { [weak self] updatedCommentCount in
            self?.updateCommentCount(updatedCommentCount)
            // Refresh inline comments
            self?.fetchCommentCount()
        }
        let navController = UINavigationController(rootViewController: commentsVC)
        present(navController, animated: true)
    }
    
    @objc private func streetViewToggleButtonTapped() {
        Logger.debug("🔘 PlaceDetailViewController: Street view toggle button tapped")
        Logger.debug("  - Current state - showingStreetView: \(showingStreetView)")
        Logger.debug("  - placePhotos.count: \(placePhotos.count)")
        Logger.debug("  - currentPhotoIndex: \(currentPhotoIndex)")
        
        // Toggle street view state
        if isStreetViewAvailable {
            showingStreetView.toggle()
            
            if showingStreetView {
                // Load street view if needed
                if streetViewImage == nil {
                    loadStreetViewImage()
                }
                streetViewToggleButton.setTitle("Photos", for: .normal)
                streetViewToggleButton.setImage(UIImage(systemName: "photo"), for: .normal)
            } else {
                streetViewToggleButton.setTitle("Look Around", for: .normal)
                streetViewToggleButton.setImage(UIImage(systemName: "eye.circle"), for: .normal)
            }
            
            // Update the media carousel
            updateMediaCarousel()
        }
    }
    
    private func checkStreetViewAvailability() {
        lookAround.checkAvailability()
    }
    
    private func loadStreetViewImage() {
        lookAround.loadImage()
    }
    
    private func autoLoadStreetView() {
        lookAround.autoLoad()
    }
    
    private func updateImageView() {
        if showingStreetView, let streetViewImage = streetViewImage {
            // Update media carousel with street view
            updateMediaCarousel()
            
            // Update button based on whether we have photos to go back to
            if !placePhotos.isEmpty || customImage != nil {
                streetViewToggleButton.setTitle("Photos", for: .normal)
                streetViewToggleButton.setImage(UIImage(systemName: "photo"), for: .normal)
            } else {
                // No photos, so button should show as "Hide Look Around" or similar
                streetViewToggleButton.setTitle("Close", for: .normal)
                streetViewToggleButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
            }
        } else {
            // Reset to original photo or icon
            if !placePhotos.isEmpty && currentPhotoIndex < placePhotos.count {
                // Update media carousel
                updateMediaCarousel()
            } else if customImage != nil {
                // Update media carousel
                updateMediaCarousel()
            } else {
                // No photos available, show default icon
                configureDefaultImage()
            }
            
            if isStreetViewAvailable {
                streetViewToggleButton.setTitle("Look Around", for: .normal)
                streetViewToggleButton.setImage(UIImage(systemName: "eye.circle"), for: .normal)
            }
        }
    }
    
    private func configureDefaultImage() {
        // Check if we have a custom image (for Home/Work places or user-uploaded)
        if customImage != nil {
            // Update media carousel
            updateMediaCarousel()
            return
        }
        
        // Check if we have stored photo URLs
        if let photos = place.photos, !photos.isEmpty, let firstPhotoUrl = photos.first {
            // Load from URL if available
            loadPhotoFromURL(firstPhotoUrl)
            return
        }
        
        // If we have street view available and no photos, show it
        if streetViewImage != nil {
            // Update media carousel with street view
            updateMediaCarousel()
            showingStreetView = true
            streetViewToggleButton.isHidden = true // Hide toggle when street view is the only option
            return
        }
        
        // If no photos or street view, use category icon from centralized property
        // Update media carousel with default icon
        updateMediaCarousel()
    }
    
    // MARK: - Notes Handling
    
    @objc private func notesLabelTapped() {
        showNotesEditor()
    }
    
    @objc private func notesEditButtonTapped() {
        showNotesEditor()
    }
    
    @objc private func addNotesButtonTapped() {
        showNotesEditor()
    }
    
    @objc private func descriptionLabelTapped(_ gesture: UITapGestureRecognizer) {
        if let url = descriptionLabel.link(at: gesture.location(in: descriptionLabel)) {
            UIApplication.shared.open(url)
        }
    }
    
    private func createAttributedDescription(from text: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        
        // Apply default attributes
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: Constants.FontSize.medium),
            .foregroundColor: Constants.Colors.gray
        ]
        attributedString.addAttributes(defaultAttributes, range: NSRange(location: 0, length: text.count))
        
        // "Website: https://…" lines: style the URL as clickable
        for link in PlaceDescriptionLinks.websiteLinks(in: text) {
            let urlAttributes: [NSAttributedString.Key: Any] = [
                .link: link.url,
                .foregroundColor: UIColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            attributedString.addAttributes(urlAttributes, range: link.range)
        }
        
        return attributedString
    }
    
    /// Our private note may live on our OWN save record (see PlaceNotesEditController).
    func loadMySaveOfVenueIfNeeded() {
        notesEdit.loadMySaveOfVenueIfNeeded()
    }

    private func showNotesEditor() {
        notesEdit.presentEditor()
    }
    
    // MARK: - Photo Loading
    
    // Removed loadGooglePlacePhoto function to avoid unnecessary API calls
    // All place data including photos should be stored when the place is created
    
    private func loadPhotoFromURL(_ urlString: String) {
        // Media carousel now handles photo loading
        updateMediaCarousel()
    }
    
    private func setDefaultCategoryIcon() {
        // Media carousel now handles default icons
        updateMediaCarousel()
    }
    
    // MARK: - Image Handling for Home/Work
    
    @objc private func editImageButtonTapped(_ sender: UIButton) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        // Use MediaCaptureService for photo and video
        actionSheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
            self?.mediaCaptureService.presentCamera(from: self!, for: .photo)
        })
        
        actionSheet.addAction(UIAlertAction(title: "Record Video", style: .default) { [weak self] _ in
            self?.mediaCaptureService.presentCamera(from: self!, for: .video)
        })
        
        actionSheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.mediaCaptureService.presentPhotoLibrary(from: self!, for: .both)
        })
        
        // Owner-only entries: these mutate the place's own image via the
        // legacy path, so only the person who added the place gets them
        let isPlaceOwner = place.isAddedByCurrentUser || isHomeOrWorkPlace

        // Add street view option if available
        if isPlaceOwner && isStreetViewAvailable && streetViewImage != nil {
            actionSheet.addAction(UIAlertAction(title: "Use Street View", style: .default) { [weak self] _ in
                self?.useStreetViewAsCustomImage()
            })
        }

        if isPlaceOwner && (customImage != nil || (place.photos != nil && !place.photos!.isEmpty)) {
            actionSheet.addAction(UIAlertAction(title: "Remove Photo", style: .destructive) { [weak self] _ in
                self?.removeCustomImage()
            })
        }
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Anchor to the button that was actually tapped — modern iOS pins
        // action sheets to their source view, so anchoring to the top carousel
        // button made the sheet appear at the top of the screen when opened
        // from the photos-section buttons at the bottom
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }

        present(actionSheet, animated: true)
    }
    
    // Old UIImagePickerController methods removed - now using MediaCaptureService
    
    private func removeCustomImage() {
        customImage = nil
        saveImage(nil)
        configureDefaultImage()
        editImageButton.setTitle("Add Photo", for: .normal)
        
        // Update photo section buttons
        addPhotoButton.isHidden = false
        photosEditButton.isHidden = true
    }
    
    private func useStreetViewAsCustomImage() {
        guard let streetViewImage = streetViewImage else { return }
        customImage = streetViewImage
        showingStreetView = false
        editImageButton.setTitle("Add Photo or Video", for: .normal)
        saveImage(streetViewImage)
        updateImageView()
        
        // Update photo section buttons
        addPhotoButton.isHidden = true
        photosEditButton.isHidden = false
        
        // Show success message
        showSuccess("Street view image set as the place photo.")
    }
    
    private func loadSavedImage() {
        let imageKey = "place_image_\(place.id)"
        if let imageData = UserDefaults.standard.data(forKey: imageKey),
           let image = UIImage(data: imageData) {
            customImage = image
            updateMediaCarousel()
        }
    }
    
    private func loadPlacePhotos() {
        // First check if place has photos from the API
        if let photos = place.photos, !photos.isEmpty {
            Logger.debug("🖼️ PlaceDetailViewController: Loading \(photos.count) photos for place: \(place.name)")
            Logger.debug("📸 DEBUG: Photo URLs from place object:")
            for (index, photo) in photos.enumerated() {
                Logger.debug("  Photo \(index + 1): \(photo)")
                // Check if it's a Google or Apple photo
                if photo.contains("firebasestorage") || photo.contains("googleapis") {
                    Logger.debug("    Type: Firebase Storage")
                } else {
                    Logger.debug("    Type: Unknown")
                }
            }
            
            // Load all photos from the API
            placePhotos.removeAll()
            Logger.debug("📸 DEBUG: Cleared placePhotos array, starting fresh load...")
            let loadGroup = DispatchGroup()
            
            for (index, photoUrl) in photos.enumerated() {
                guard let url = URL(string: photoUrl) else { 
                    Logger.debug("❌ PlaceDetailViewController: Invalid photo URL at index \(index): \(photoUrl)")
                    continue 
                }
                
                loadGroup.enter()
                URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                    if let error = error {
                        Logger.debug("❌ PlaceDetailViewController: Error loading photo \(index): \(error)")
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        Logger.debug("📡 PlaceDetailViewController: Photo \(index) HTTP Status: \(httpResponse.statusCode)")
                    }
                    
                    if let data = data, let image = UIImage(data: data) {
                        Logger.debug("✅ PlaceDetailViewController: Successfully loaded photo \(index)")
                        DispatchQueue.main.async {
                            self?.placePhotos.append((image: image, url: photoUrl))
                        }
                    } else {
                        Logger.debug("❌ PlaceDetailViewController: Failed to create image from data for photo \(index)")
                    }
                    loadGroup.leave()
                }.resume()
            }
            
            loadGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                
                Logger.debug("🏁 PlaceDetailViewController: Finished loading photos. Total loaded: \(self.placePhotos.count)")
                Logger.debug("📸 DEBUG: placePhotos array now contains \(self.placePhotos.count) UIImages")
                
                // Update media carousel
                Logger.debug("📸 DEBUG: Calling updateMediaCarousel()...")
                self.updateMediaCarousel()
                
                // Update UI if photos were loaded
                if !self.placePhotos.isEmpty {
                    self.editImageButton.setTitle("Add Photo or Video", for: .normal)
                    
                    // Update photo section buttons
                    if self.place.isAddedByCurrentUser || self.isHomeOrWorkPlace {
                        self.addPhotoButton.isHidden = true
                        self.photosEditButton.isHidden = false
                    }
                } else {
                    Logger.debug("⚠️ PlaceDetailViewController: No photos were successfully loaded")
                }
                
                // Update street view toggle button visibility
                self.updateToggleButtonVisibility()
            }
        } else if isHomeOrWorkPlace {
            // For home/work places, check local storage
            loadSavedImage()
            // Update button title if image exists
            if customImage != nil {
                editImageButton.setTitle("Add Photo or Video", for: .normal)
                // Update photo section buttons
                addPhotoButton.isHidden = true
                photosEditButton.isHidden = false
            }
            updateToggleButtonVisibility()
        } else {
            updateToggleButtonVisibility()
        }
    }
    
    private func updateToggleButtonVisibility() {
        // Show toggle button only if Apple Look Around is available
        // Photo navigation is now handled by MediaCarouselView
        let shouldShowToggle = isStreetViewAvailable
        
        Logger.debug("🔘 PlaceDetailViewController: Toggle button visibility check:")
        Logger.debug("  - isStreetViewAvailable: \(isStreetViewAvailable)")
        Logger.debug("  - shouldShowToggle: \(shouldShowToggle)")
        
        streetViewToggleButton.isHidden = !shouldShowToggle
        
        // Only show "Look Around" functionality
        if isStreetViewAvailable {
            streetViewToggleButton.setTitle("Look Around", for: .normal)
            streetViewToggleButton.setImage(UIImage(systemName: "eye.circle"), for: .normal)
        }
    }
    
    private func saveImage(_ image: UIImage?) {
        // For home/work places, save locally
        if isHomeOrWorkPlace {
            let imageKey = "place_image_\(place.id)"
            
            if let image = image,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                UserDefaults.standard.set(imageData, forKey: imageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: imageKey)
            }
        } else {
            // For regular places, upload to API
            guard let image = image else {
                // If removing image, we could implement photo removal here
                return
            }
            
            guard !isLoadingPhoto else { return }
            isLoadingPhoto = true
            
            // Show loading indicator
            editImageButton.isEnabled = false
            
            // Compress image
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                isLoadingPhoto = false
                editImageButton.isEnabled = true
                showAlert(title: "Error", message: "Failed to process image")
                return
            }
            
            // Upload to API
            PlaceService.shared.updatePlace(
                id: place.id,
                addPhotos: [imageData]
            ) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoadingPhoto = false
                    self?.editImageButton.isEnabled = true
                    
                    switch result {
                    case .success(let updatedPlace):
                        // Update the local place object with the server response
                        self?.place = updatedPlace
                        
                        // The image we just uploaded is already in memory as 'image'
                        // No need to re-download it
                        self?.customImage = image
                        self?.updateMediaCarousel()
                        
                        // Update button titles
                        self?.editImageButton.setTitle("Change Photo", for: .normal)
                        
                        // Update photo section buttons
                        self?.addPhotoButton.isHidden = true
                        self?.photosEditButton.isHidden = false
                        
                        // Show success message
                        self?.showAlert(title: "Success", message: "Photo uploaded successfully")
                        
                        // Clear any existing photos array to force reload if view is refreshed
                        self?.placePhotos.removeAll()
                        if let photos = updatedPlace.photos, !photos.isEmpty {
                            self?.placePhotos.append((image: image, url: photos.last))
                        }
                        
                    case .failure(let error):
                        self?.showAlert(title: "Error", message: "Failed to upload photo: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Actions
    
    
    @objc private func updateAddressButtonTapped() {
        // Create and present the address search view controller
        let searchVC = PlaceAddressSearchViewController(
            placeName: place.name,
            currentLocation: place.location?.clLocation
        )
        searchVC.delegate = self
        
        let navController = UINavigationController(rootViewController: searchVC)
        present(navController, animated: true)
    }
    
    private func performAddressUpdate(_ newAddress: String, coordinate: CLLocationCoordinate2D? = nil) {
        // Show loading
        let loadingAlert = AlertPresenter.showLoading(message: "Saving new address and location...", from: self)
        present(loadingAlert, animated: true)
        
        // Call the API to update the address and coordinates
        PlaceService.shared.updatePlaceAddress(id: place.id, address: newAddress, coordinate: coordinate) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let updatedPlace):
                        // Update the UI with new place data
                        self.place = updatedPlace
                        self.addressLabel.text = updatedPlace.address
                        
                        // Update map if location changed
                        if let location = updatedPlace.location?.clLocation {
                            self.mapView.removeAnnotations(self.mapView.annotations)
                            
                            let annotation = MKPointAnnotation()
                            annotation.coordinate = location.coordinate
                            annotation.title = updatedPlace.name
                            self.mapView.addAnnotation(annotation)
                            
                            let region = MKCoordinateRegion(
                                center: location.coordinate,
                                latitudinalMeters: 1000,
                                longitudinalMeters: 1000
                            )
                            self.mapView.setRegion(region, animated: true)
                        }
                        
                        // Show success message
                        self.showSuccess("Location and address have been updated successfully")
                        
                        // Post notification to refresh any lists
                        NotificationCenter.default.post(name: NSNotification.Name("PlaceUpdated"), object: nil, userInfo: ["place": updatedPlace])
                        
                    case .failure(let error):
                        // Show error message
                        let errorMessage = "Failed to update address: \(error.localizedDescription)"
                        AlertPresenter.showError(title: "Unable to Update", message: errorMessage, from: self)
                    }
                }
            }
        }
    }
}

// MARK: - PlaceAddressSearchViewControllerDelegate
extension PlaceDetailViewController: PlaceAddressSearchViewControllerDelegate {
    func placeAddressSearchViewController(_ controller: PlaceAddressSearchViewController, didSelectMapItem mapItem: MKMapItem) {
        // Extract address and coordinates from the map item
        let placemark = mapItem.placemark
        
        // Format address
        let address = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode
        ].compactMap { $0 }.joined(separator: ", ")
        
        // Get coordinates
        let coordinate = placemark.coordinate
        
        // Update the place with new address and coordinates
        performAddressUpdate(address, coordinate: coordinate)
    }
    
    func placeAddressSearchViewControllerDidCancel(_ controller: PlaceAddressSearchViewController) {
        // Just dismiss, nothing else needed
    }
}

// MARK: - EditPlaceDelegate
extension PlaceDetailViewController: EditPlaceDelegate {
    func didUpdatePlace(_ updatedPlace: Place) {
        // Update the current place with the updated one
        self.place = updatedPlace
        
        // Refresh the UI with the updated place data
        configureUI()
        
        // Update the title in case place name changed
        title = place.name
        
        // Stay on the current screen to show the updated changes
        Logger.debug("🔄 Place updated: \(updatedPlace.name) with category: \(updatedPlace.displayCategory)")
    }
    
    func didDeletePlace(_ placeId: String) {
        // Navigate back to the circle detail view after deletion
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - CircleSelectionDelegate
extension PlaceDetailViewController: CircleSelectionDelegate {
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle) {
        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Moving \(place.name) to \(circle.name)...", from: self)
        
        // Perform the move
        PlaceService.shared.movePlaceToCircle(placeId: place.id, targetCircleId: circle.id) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let updatedPlace):
                        // Update the local place object
                        self.place = updatedPlace
                        self.circle = circle
                        
                        // Update the circle info in the UI
                        self.circleNameLabel.text = circle.name
                        
                        // Show success message
                        self.showSuccess("\(self.place.name) has been moved to \(circle.name)") {
                            // Pop back to the previous view controller since the place has moved
                            self.navigationController?.popViewController(animated: true)
                        }
                        
                    case .failure(let error):
                        self.showError("Failed to move place: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func circleSelectionViewControllerDidCancel(_ controller: CircleSelectionViewController) {
        // User cancelled, nothing to do
    }
}

// MARK: - MediaCaptureServiceDelegate
extension PlaceDetailViewController: MediaCaptureServiceDelegate {
    func mediaCaptureService(_ service: MediaCaptureService, didCapture media: CapturedMedia) {
        switch media.type {
        case .photo(let image):
            handleCapturedPhoto(image)
        case .video(let videoURL):
            handleCapturedVideo(url: videoURL)
        }
    }
    
    func mediaCaptureService(_ service: MediaCaptureService, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoadingPhoto = false
            self?.updateImageView()
            self?.showError(error)
        }
    }
    
    func mediaCaptureServiceDidCancel(_ service: MediaCaptureService) {
        // User cancelled - no action needed
    }
    
    // MARK: - Media Handling (Using Shared Services)
    
    private func handleCapturedPhoto(_ image: UIImage) {
        isLoadingPhoto = true
        updateImageView()
        
        // Show immediate feedback to user
        showSuccess("Processing photo...")
        
        // Use MediaProcessingService for consistent compression (same as Moments)
        mediaProcessingService.processPhoto(image) { [weak self] result in
            switch result {
            case .success(let processedPhoto):
                self?.uploadProcessedPhoto(processedPhoto)
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.isLoadingPhoto = false
                    self?.updateImageView()
                    self?.showError(error)
                }
            }
        }
    }
    
    private func handleCapturedVideo(url: URL) {
        isLoadingPhoto = true
        updateImageView()
        
        // Use MediaProcessingService for consistent compression (same as Moments)
        mediaProcessingService.processVideo(at: url) { [weak self] result in
            switch result {
            case .success(let processedVideo):
                self?.uploadProcessedVideo(processedVideo)
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.isLoadingPhoto = false
                    self?.updateImageView()
                    self?.showError(error)
                }
            }
        }
    }
    
    private func uploadProcessedPhoto(_ processedPhoto: ProcessedPhoto) {
        // Show upload progress feedback
        showSuccess("Uploading photo...")
        
        // Use MediaStorageService for consistent upload handling (same as Moments)
        mediaStorageService.uploadPhoto(
            processedPhoto,
            for: place,
            type: .placePhoto,
            visibility: "public",
            progress: { [weak self] progress in
                // Update user with upload progress
                DispatchQueue.main.async {
                    let percentage = Int(progress.progress * 100)
                    switch progress.phase {
                    case .initiating:
                        self?.showSuccess("Preparing upload...")
                    case .uploading:
                        self?.showSuccess("Uploading... \(percentage)%")
                    case .finalizing:
                        self?.showSuccess("Finalizing upload...")
                    case .completed:
                        break // Will be handled in completion
                    }
                }
            }
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingPhoto = false
                self?.updateImageView()
                
                switch result {
                case .success(let storageResult):
                    // Update place with new image - add to carousel
                    self?.customImage = processedPhoto.image
                    self?.placePhotos.append((image: processedPhoto.image, url: storageResult.storageUrls["photoUrl"]))

                    // Update photo section buttons
                    self?.addPhotoButton.isHidden = true
                    self?.photosEditButton.isHidden = false

                    // Show the new photo immediately; the GlobalPlace refresh below
                    // replaces it with the attributed server copy when it lands
                    self?.updateMediaCarousel()

                    Logger.debug("✅ [PlaceDetailViewController] Photo upload successful, refreshing Global Place data...")

                    // Clear any cached data and refresh Global Place data
                    self?.globalPlace = nil
                    self?.loadGlobalPlaceData()
                    
                    self?.showSuccess("Photo uploaded successfully")
                    
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
    
    private func uploadProcessedVideo(_ processedVideo: ProcessedVideo) {
        // Use MediaStorageService for consistent upload handling (same as Moments)
        mediaStorageService.uploadVideo(
            processedVideo,
            for: place,
            type: .placeVideo,
            visibility: "public"
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingPhoto = false
                self?.updateImageView()
                
                switch result {
                case .success(let storageResult):
                    self?.showSuccess("Video uploaded successfully")
                    self?.updateMediaCarousel()
                    
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
}

// MARK: - MediaCarouselViewDelegate
extension PlaceDetailViewController: MediaCarouselViewDelegate {
    func mediaCarouselView(_ carouselView: MediaCarouselView, didTapVideoAt index: Int, url: String) {
        // Play video when tapped
        guard let videoURL = URL(string: url) else { return }
        
        let player = AVPlayer(url: videoURL)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        
        present(playerViewController, animated: true) {
            player.play()
        }
    }

    func mediaCarouselView(_ carouselView: MediaCarouselView, didSetPhotoLiked liked: Bool, photo: AttributedPhoto) {
        guard let photoId = photo.photoId else { return }

        // The carousel already toggled the heart optimistically — persist it,
        // and re-sync from the server if the request fails
        GlobalPlaceService.shared.setPhotoLiked(
            placeId: place.globalPlaceId ?? place.id,
            photoId: photoId,
            liked: liked
        ) { [weak self] result in
            switch result {
            case .success(let response):
                // First like on someone else's photo earns a nickel — the
                // fractional deposit plays the leprechaun (no-op otherwise)
                if liked {
                    PiggyBankDepositView.play(credit: response.piggyBank)
                }
            case .failure(let error):
                Logger.debug("❌ [PlaceDetailViewController] Photo like failed, re-syncing: \(error)")
                DispatchQueue.main.async {
                    self?.loadGlobalPlaceData()
                }
            }
        }
    }
}

// MARK: - Add Place to Circle
extension PlaceDetailViewController {
    private func addPlaceToCircle(_ circle: Circle) {
        // Check if this is from a check-in (place not in any of user's circles)
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let isFromCheckIn = place.circleId == nil || place.circleId!.isEmpty || // Check-in places might have empty circleId
                           (!userCircles.contains { $0.id == place.circleId } && // Not in user's circles
                            place.addedBy != currentUserId) // And not added by current user
        
        if isFromCheckIn {
            // New flow: Open AddPlaceViewController with pre-filled data
            let addPlaceVC = AddPlaceViewController(circleId: circle.id)
            let navController = UINavigationController(rootViewController: addPlaceVC)
            navController.modalPresentationStyle = .fullScreen
            
            present(navController, animated: true) {
                // Pre-fill with place data after presentation
                addPlaceVC.prefillWithPlace(self.place)
            }
        } else {
            // Existing flow: Copy place between user's circles
            // Show loading indicator
            let loadingAlert = AlertPresenter.showLoading(message: "Adding Place...", from: self)
            
            // Add the place to the selected circle
            PlaceService.shared.addExistingPlaceToCircle(placeId: place.id, circleId: circle.id) { [weak self] result in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        switch result {
                        case .success(let newPlace):
                            // Update to the new place copy that was created in the user's circle
                            self?.place = newPlace
                            
                            // Reload the UI with the new place
                            self?.configureUI()
                            
                            // Update the navigation title to show it's now in user's circle
                            self?.navigationItem.title = newPlace.name
                            
                            // Hide the add button since this place is now in user's circle
                            self?.setAddToCircleVisible(false)
                            self?.updateAddressTitleConstraint()
                            
                            // Show update info button if the place needs photos
                            let hasAPIPhotos = (newPlace.photos?.count ?? 0) > 0
                            let hasCustomImage = self?.customImage != nil
                            let showingStreetView = self?.showingStreetView ?? false
                            let isShowingDefaultIcon = !hasCustomImage && !hasAPIPhotos && !showingStreetView
                            let canSearchGooglePlaces = newPlace.googlePlaceId != nil || newPlace.location != nil
                            // self?.updateInfoButton.isHidden = !isShowingDefaultIcon || !canSearchGooglePlaces // Commented - automatic migration
                            
                            // Show success message
                            let alert = UIAlertController(
                                title: "Success",
                                message: "Place added to \(circle.name)",
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "OK", style: .default))
                            self?.present(alert, animated: true)
                            
                            // Post notification to refresh circles if needed
                            NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
                            
                        case .failure(let error):
                            // Provide more specific error messages
                            var errorMessage = "Failed to add place"
                            
                            if let placeError = error as? PlaceError {
                                errorMessage = placeError.errorDescription ?? errorMessage
                            } else if (error as NSError).code == 401 {
                                errorMessage = "You don't have permission to add places to this circle"
                            } else if (error as NSError).code == 404 {
                                errorMessage = "The place or circle was not found"
                            } else if (error as NSError).code == 400 {
                                errorMessage = "This place is already in the selected circle. If you just deleted it, please wait a moment and try again."
                            } else {
                                errorMessage = "Failed to add place: \(error.localizedDescription)"
                            }
                            
                            AlertPresenter.showError(message: errorMessage, from: self!)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Like and Comment Helpers
extension PlaceDetailViewController {
    private func updateFollowButton() {
        if isFollowingPlace {
            followButton.setTitle("Following", for: .normal)
            followButton.setStyle(.following)
        } else {
            followButton.setTitle("Follow", for: .normal)
            followButton.setStyle(.primary)
        }
    }

    /// Seed follow state from a server-fresh place copy (list copies may not carry it)
    private func syncFollowState(from updatedPlace: Place) {
        if let following = updatedPlace.isFollowing {
            isFollowingPlace = following
        }
        if let count = updatedPlace.followersCount {
            placeFollowersCount = count
        }
        updateFollowButton()
    }

    private func updateLikeButton() {
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let isLiked = place.likes?.contains(currentUserId) ?? false
        
        // Update heart icon
        let heartImage = isLiked ? "heart.fill" : "heart"
        likeButton.setImage(UIImage(systemName: heartImage, withConfiguration: PlaceDetailViewController.actionIconConfig), for: .normal)
        likeButton.tintColor = isLiked ? UIColor.systemRed : .label
        
        // Update like count - blank instead of a noisy "0"
        let likeCount = place.likesCount ?? place.likes?.count ?? 0
        likeCountLabel.text = likeCount > 0 ? "\(likeCount)" : ""
    }
    
    private func fetchCommentCount() {
        PlaceService.shared.getPlaceComments(placeId: place.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let comments):
                    self?.updateCommentCount(comments.count)
                    self?.displayInlineComments(comments)
                case .failure(let error):
                    Logger.error("Failed to fetch comments: \(error)")
                    self?.commentCountLabel.text = ""
                    self?.commentsSection.isHidden = true
                }
            }
        }
    }
    
    private func displayInlineComments(_ comments: [PlaceComment]) {
        // Clear existing comment views
        commentsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        displayedComments = comments
        
        // Show comments section if there are comments
        if comments.isEmpty {
            commentsSection.isHidden = true
            return
        }
        
        commentsSection.isHidden = false
        
        // Show only the first 3 comments
        let commentsToShow = Array(comments.prefix(3))
        
        // Update "View all" button text
        if comments.count > 3 {
            viewAllCommentsButton.setTitle("View all \(comments.count)", for: .normal)
            viewAllCommentsButton.isHidden = false
        } else {
            viewAllCommentsButton.isHidden = true
        }
        
        // Create comment views
        for comment in commentsToShow {
            let commentView = createInlineCommentView(comment)
            commentsStackView.addArrangedSubview(commentView)
        }
    }
    
    private func createInlineCommentView(_ comment: PlaceComment) -> UIView {
        let row = PlaceCommentRowView(comment: comment)
        row.onLikeTapped = { [weak self, weak row] button in
            guard let self = self, let row = row else { return }
            self.toggleInlineCommentLike(commentId: comment.id, sender: button, row: row)
        }
        return row
    }
    
    private func updateCommentCount(_ count: Int) {
        commentCountLabel.text = count > 0 ? "\(count)" : ""
    }
    
    private func toggleInlineCommentLike(commentId: String, sender: UIButton, row: PlaceCommentRowView) {
        // Look the comment up fresh — the list can have been reloaded since
        // this row was built
        guard let comment = displayedComments.first(where: { $0.id == commentId }) else { return }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // Disable button during request
        sender.isEnabled = false
        
        PlaceService.shared.likeComment(placeId: place.id, commentId: comment.id) { [weak self] result in
            DispatchQueue.main.async {
                sender.isEnabled = true
                
                switch result {
                case .success(let (liked, likesCount, piggyBank)):
                    // Update heart and count
                    row.setLiked(liked, count: likesCount)

                    // FavCoins for the heart (leprechaun for the fraction)
                    PiggyBankDepositView.play(credit: piggyBank)
                    
                    // Show animation
                    UIView.animate(withDuration: 0.1, animations: {
                        sender.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                    }) { _ in
                        UIView.animate(withDuration: 0.1) {
                            sender.transform = .identity
                        }
                    }
                    
                case .failure(let error):
                    Logger.error("Failed to like comment: \(error)")
                    self?.showError("Failed to update like. Please try again.")
                }
            }
        }
    }
}

// MARK: - PlaceVenueRewardsViewDelegate
extension PlaceDetailViewController: PartnerActionsRowViewDelegate {
    func partnerActionsRow(_ view: PartnerActionsRowView, didTap group: PartnerActionGroup, sourceView: UIView) {
        let providers = PartnerActionsService.shared.usableProviders(in: group, for: place)
        guard !providers.isEmpty else { return }
        if providers.count == 1 {
            PartnerActionsService.shared.open(provider: providers[0], group: group, place: place, from: self)
            return
        }
        // Multi-provider group: pick via action sheet, anchored to the chip
        // so iPad presents a popover instead of crashing
        let actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = providers.map { provider in
            (title: provider.title, style: .default, handler: { [weak self] in
                guard let self = self else { return }
                PartnerActionsService.shared.open(provider: provider, group: group, place: self.place, from: self)
            })
        }
        AlertPresenter.showActionSheet(
            title: group.sheetTitle,
            actions: actions,
            from: self,
            sourceView: sourceView
        )
    }
}

extension PlaceDetailViewController: PlaceVenueRewardsViewDelegate {

    func placeVenueView(_ view: PlaceVenueRewardsView, didTapRedeem offer: RewardOffer, venue: PlaceVenue) {
        confirmAndRedeemOffer(offer, venueId: venue.venueId, venueName: venue.venueName) { [weak self] _ in
            // Refresh balance/affordability behind the voucher screen
            self?.loadVenueRewards()
        }
    }

    func placeVenueViewDidTapClaim(_ view: PlaceVenueRewardsView) {
        // Ownership is verified by a human: the claimer's contact info is
        // emailed to the admin, who approves or denies.
        AlertPresenter.showMultiFieldInput(
            title: "Claim \(place.name)",
            message: "Tell us how to reach you — we'll verify that you own this business and set you up as its owner.",
            fields: [
                (placeholder: "Your name", keyboardType: .default, initialText: nil),
                (placeholder: "Business email", keyboardType: .emailAddress, initialText: nil),
                (placeholder: "Phone (optional)", keyboardType: .phonePad, initialText: nil)
            ],
            confirmTitle: "Submit claim",
            from: self
        ) { [weak self] values in
            guard let self = self else { return }
            let contactName = values.count > 0 ? values[0]?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            let contactEmail = values.count > 1 ? values[1]?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            let contactPhone = values.count > 2 ? values[2]?.trimmingCharacters(in: .whitespacesAndNewlines) : nil

            guard let name = contactName, !name.isEmpty,
                  let email = contactEmail, !email.isEmpty, email.contains("@") else {
                self.showError("Please provide your name and a valid business email so we can verify your claim.")
                return
            }

            let loading = AlertPresenter.showLoading(message: "Submitting...", from: self)
            RewardsService.shared.claimPlace(
                placeId: self.place.globalPlaceId ?? self.place.id,
                googlePlaceId: self.place.googlePlaceId,
                contactName: name,
                contactEmail: email,
                contactPhone: contactPhone
            ) { [weak self] result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        guard let self = self else { return }
                        switch result {
                        case .success:
                            self.showSuccess("Claim submitted — we'll be in touch after we verify your ownership.")
                            self.loadVenueRewards()
                        case .failure(let error):
                            self.showError(error)
                        }
                    }
                }
            }
        }
    }

    func placeVenueViewDidTapManage(_ view: PlaceVenueRewardsView, venue: PlaceVenue) {
        openVenueManagement(venue)
    }

    func placeVenueViewDidTapStats(_ view: PlaceVenueRewardsView, venue: PlaceVenue) {
        let dashboardVC = VenueDashboardViewController(venueId: venue.venueId, venueName: venue.venueName)
        navigationController?.pushViewController(dashboardVC, animated: true)
    }

    func placeVenueView(_ view: PlaceVenueRewardsView, didTapQuickAction action: PlaceVenueRewardsView.QuickAction, venue: PlaceVenue) {
        switch action {
        case .announcement:
            // The compose flows live on the manage screen; deep-link and fire
            // the composer as soon as it appears
            openVenueManagement(venue, quickAction: .addAnnouncement)
        case .offer:
            openVenueManagement(venue, quickAction: .addOffer)
        }
    }

    func placeVenueViewDidTapUpgrade(_ view: PlaceVenueRewardsView) {
        let paywallVC = OwnerPaywallViewController()
        paywallVC.venueId = placeVenueData?.venue?.venueId
        paywallVC.onSubscribed = { [weak self] in
            // Reload so the teaser disappears and the store card reflects
            // the unlocked state
            self?.loadVenueRewards()
        }
        navigationController?.pushViewController(paywallVC, animated: true)
    }

    /// The owner's single nav affordance: preview the page as a customer.
    /// Toggles with the same button (eye ⇄ eye.slash).
    @objc func ownerPreviewNavButtonTapped() {
        ownerEdit.toggleViewAsCustomer()
    }

    private func addOwnerPreviewNavButtonIfNeeded() {
        let alreadyAdded = navigationItem.rightBarButtonItems?.contains {
            $0.accessibilityLabel == "View as Customer"
        } ?? false
        guard !alreadyAdded else { return }

        let previewButton = UIBarButtonItem(
            image: UIImage(systemName: "eye"),
            style: .plain,
            target: self,
            action: #selector(ownerPreviewNavButtonTapped)
        )
        previewButton.accessibilityLabel = "View as Customer"
        navigationItem.rightBarButtonItems = (navigationItem.rightBarButtonItems ?? []) + [previewButton]
    }

    private var ownerPreviewNavButton: UIBarButtonItem? {
        navigationItem.rightBarButtonItems?.first { $0.accessibilityLabel == "View as Customer" }
    }

    private func openVenueManagement(_ venue: PlaceVenue, quickAction: VenueManageViewController.QuickAction? = nil) {
        // The owner usually got HERE from the manage screen ("Your place
        // page"). Pushing another copy grows the stack in a loop — pop back
        // to the existing one instead (carrying any quick action with us).
        if let stack = navigationController?.viewControllers,
           let existing = stack.compactMap({ $0 as? VenueManageViewController })
               .last(where: { $0.venueId == venue.venueId }) {
            existing.pendingQuickAction = quickAction
            navigationController?.popToViewController(existing, animated: true)
            return
        }
        let loading = AlertPresenter.showLoading(message: "Loading...", from: self)
        RewardsService.shared.getMyVenues { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let venues):
                        if let match = venues.first(where: { $0.venueId == venue.venueId }) {
                            let manageVC = VenueManageViewController(venue: match)
                            manageVC.pendingQuickAction = quickAction
                            self.navigationController?.pushViewController(manageVC, animated: true)
                        } else {
                            // Super-users manage venues they don't own — fall back to the full list
                            self.pushVenueManageFromAllVenues(venueId: venue.venueId)
                        }
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func pushVenueManageFromAllVenues(venueId: String) {
        RewardsService.shared.listVenues { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let venues):
                    if let match = venues.first(where: { $0.venueId == venueId }) {
                        let manageVC = VenueManageViewController(venue: match)
                        self.navigationController?.pushViewController(manageVC, animated: true)
                    } else {
                        self.showError("Could not load this venue's management page.")
                    }
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Owner: cover photo

    func presentCoverPhotoPicker() {
        let photos = globalPlace?.photos ?? []
        guard !photos.isEmpty else {
            AlertPresenter.showError(
                title: "No Photos Yet",
                message: "Add photos to this place first — then pick which one leads the page.",
                from: self
            )
            return
        }
        guard let venueId = placeVenueData?.venue?.venueId else { return }

        let picker = CoverPhotoPickerViewController(
            photoUrls: photos.map { $0.url },
            currentCoverUrl: globalPlace?.coverPhotoUrl
        )
        picker.onSelect = { [weak self] url in
            guard let self = self else { return }
            RewardsService.shared.setVenueCoverPhoto(venueId: venueId, url: url) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        // Re-fetch so the carousel reorders with the new cover
                        self.loadGlobalPlaceData()
                        self.showSuccess("Cover photo updated")
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
        let nav = UINavigationController(rootViewController: picker)
        present(nav, animated: true)
    }
}

// MARK: - Owner tap-to-edit (PlaceOwnerEditController)
extension PlaceDetailViewController: PlaceOwnerEditControllerDelegate {
    var placeForOwnerEdit: Place { place }

    func ownerEditRequestsAddressUpdate() {
        updateAddressButtonTapped()
    }

    func ownerEditDidUpdatePlace(_ updated: Place) {
        place = updated
        configureUI()
    }

    func ownerEditDidChangeAboutContent() {
        updateAboutCardVisibility()
    }

    /// The eye button itself flips (eye ⇄ eye.slash) so the way back is
    /// always visible; the store card re-renders for the chosen audience.
    func ownerEditDidToggleCustomerView(_ viewingAsCustomer: Bool) {
        venueRewardsView.viewAsCustomer = viewingAsCustomer
        venueRewardsView.configure(with: placeVenueData)
        ownerPreviewNavButton?.image = UIImage(systemName: viewingAsCustomer ? "eye.slash" : "eye")
    }

    /// About card collapses entirely when none of description, hours, the
    /// saver's rating, or the owner's edit rows have content (hidden
    /// arranged subviews already collapse in-stack).
    func updateAboutCardVisibility() {
        let aboutIsEmpty = descriptionLabel.isHidden && hoursLabel.isHidden && userRatingLabel.isHidden
            && !ownerEdit.hasVisibleOwnerRows
        aboutTitleLabel.isHidden = aboutIsEmpty
        aboutCardView.isHidden = aboutIsEmpty
        aboutTopConstraint?.constant = aboutIsEmpty ? 0 : Constants.Spacing.medium
        aboutHeightConstraint?.isActive = aboutIsEmpty
    }
}

// MARK: - VenueRewardsLoaderDelegate

extension PlaceDetailViewController: VenueRewardsLoaderDelegate {
    func currentPlace(for loader: VenueRewardsLoader) -> Place { place }

    func loader(_ loader: VenueRewardsLoader, didLoadPartnerActionGroups groups: [PartnerActionGroup]) {
        partnerActionsRowView.configure(with: groups)
        let show = !groups.isEmpty
        partnerActionsHeightConstraint?.constant = show ? 44 : 0
        partnerActionsTopConstraint?.constant = show ? Constants.Spacing.medium : 0
        view.layoutIfNeeded()
    }

    func loader(_ loader: VenueRewardsLoader, didLoadVenueData data: PlaceVenueData) {
        placeVenueData = data
        venueRewardsView.configure(with: data)
        // The card shows for enrolled venues AND for the venue-less
        // "Is this your store?" claim states — collapsing on
        // !hasVenue alone clipped the claim card to zero height
        let hasVenue = data.venue != nil
        let showsClaimCard = (data.claim?.canClaim == true) || (data.claim?.myClaimStatus != nil)
        let showCard = hasVenue || showsClaimCard
        venueRewardsHeightConstraint?.isActive = !showCard
        // Docks tight under the map — the claim card and the map
        // both describe the physical location, so they read as one
        venueRewardsTopConstraint?.constant = showCard ? Constants.Spacing.small : 0
        view.layoutIfNeeded()

        // Owners get ONE nav affordance: the eye that previews the
        // page as customers see it. Managing and editing live on
        // the Your Store card itself — the page IS the owner's
        // surface, so a toolbar of duplicate entry points just
        // read as clutter.
        ownerEdit.isVenueOwner = data.isOwner == true
        if hasVenue && data.isOwner == true {
            addOwnerPreviewNavButtonIfNeeded()
            // The page IS the owner's editor: arm the fields
            ownerEdit.decorateIfNeeded()
        }
    }

    func loaderVenueLookupFailed(_ loader: VenueRewardsLoader) {
        // Additive section — a failed lookup just leaves it collapsed
        venueRewardsView.configure(with: nil)
    }

    func loader(_ loader: VenueRewardsLoader, didLoadGlobalPlace globalPlace: GlobalPlace) {
        self.globalPlace = globalPlace
        // Refresh media carousel with attribution data
        updateMediaCarousel()
    }

    func loaderGlobalPlaceLookupFailed(_ loader: VenueRewardsLoader) {
        // Continue with legacy Place model - no attribution data
        // But update media carousel to ensure photos are shown
        updateMediaCarousel()
    }
}

// MARK: - PlaceLookAroundControllerDelegate

extension PlaceDetailViewController: PlaceLookAroundControllerDelegate {
    func currentPlace(for controller: PlaceLookAroundController) -> Place { place }

    func lookAroundAvailabilityDidChange(_ controller: PlaceLookAroundController) {
        updateToggleButtonVisibility()
    }

    func lookAroundImageDidLoad(_ controller: PlaceLookAroundController) {
        if showingStreetView == true {
            updateImageView()
        }
    }

    func lookAroundDidAutoLoad(_ controller: PlaceLookAroundController) {
        // Only show street view automatically if there are no photos
        let hasPhotos = (place.photos != nil && !place.photos!.isEmpty) || customImage != nil

        if !hasPhotos {
            // No photos available, show street view
            showingStreetView = true
            updateImageView()
            streetViewToggleButton.isHidden = true // Hide toggle when street view is the only option
            // Hide update info button since we now have street view
            // self.updateInfoButton.isHidden = true // Commented - automatic migration
            Logger.debug("PlaceDetailViewController: Auto-showing street view for place without photos")
        } else {
            // Has photos, just store street view for toggle option
            updateToggleButtonVisibility()
            Logger.debug("PlaceDetailViewController: Street view loaded but not shown (place has photos)")
        }
    }
}

// MARK: - PlaceNotesEditControllerDelegate

extension PlaceDetailViewController: PlaceNotesEditControllerDelegate {
    func currentPlace(for controller: PlaceNotesEditController) -> Place { place }
    func mySaveOfVenue(for controller: PlaceNotesEditController) -> Place? { mySaveOfVenue }

    func notesEdit(_ controller: PlaceNotesEditController, didLoadMySave mine: Place) {
        mySaveOfVenue = mine
        // Refresh just the notes section with our own note
        if let myNotes = mine.privateNotes, !myNotes.isEmpty {
            notesLabel.text = myNotes
            notesLabel.isHidden = false
            addNotesButton.isHidden = true
            notesEditButton.isHidden = false
        }
    }

    func notesEdit(_ controller: PlaceNotesEditController, didSave privateNotes: String, updatedPlace: Place) {
        // Keep the in-memory model in sync — the notes editor
        // seeds from the target record, so a stale copy would
        // show (and then re-save) the old text
        if updatedPlace.id == place.id {
            place = updatedPlace
        } else {
            mySaveOfVenue = updatedPlace
        }

        // Only the saver has a note, and only they ever see it
        let notesText = privateNotes

        if !notesText.isEmpty {
            notesLabel.text = notesText
            notesLabel.textColor = Constants.Colors.gray
            notesLabel.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
            notesLabel.isHidden = false
            addNotesButton.isHidden = true
            notesEditButton.isHidden = false
        } else {
            notesLabel.isHidden = true
            addNotesButton.isHidden = false
            notesEditButton.isHidden = true
        }
    }
}
