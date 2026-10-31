import UIKit
import CoreLocation

/// "Build my map from my photos" (Wes, 2026-10-16/17): every place in the
/// person's photos, nearest first (where they are now, else home), on the
/// review page — nothing is added until they save what they agree with —
/// into "Places from my photos". First 25 free, then Premium.
final class PhotoMapBuilderViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let savedPlaces: [Place]
    private let circles: [Circle]
    private let startsImmediately: Bool
    /// Set by the sign-up step: closing or saving ends the step
    var onFinished: (() -> Void)?

    private let iconView = UIImageView(image: UIImage(systemName: "photo.stack.fill"))
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private lazy var primaryButton = UIButton.primaryButton(title: "Build my map")
    private lazy var secondaryButton = UIButton.secondaryButton(title: "Not now")
    private var uid: String { AuthService.shared.getUserId() ?? "anon" }

    init(savedPlaces: [Place], circles: [Circle], startsImmediately: Bool = false) {
        self.savedPlaces = savedPlaces
        self.circles = circles
        self.startsImmediately = startsImmediately
        super.init(nibName: nil, bundle: nil)
        title = "Build my map"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        iconView.tintColor = Constants.Colors.primary
        iconView.contentMode = .scaleAspectFit
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = "Build your map from your photos"
        bodyLabel.font = .systemFont(ofSize: 16)
        bodyLabel.textColor = Constants.Colors.secondaryLabel
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.text = "We find the caf\u{00E9}s, restaurants, shops and other places in your photos, nearest to you first. You check the list, and only the ones you keep go into \u{201C}Places from my photos.\u{201D} Your first 25 are free.\n\nYour photos stay on your phone and are never added to places. Only where they were taken is used, and you can switch these places off your map any time."
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, bodyLabel, UIView(), primaryButton, secondaryButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 64),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        primaryButton.addTarget(self, action: #selector(start), for: .touchUpInside)
        secondaryButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        if startsImmediately { start() }
    }

    @objc private func start() {
        AnalyticsService.shared.logEvent("photo_map_started", parameters: [:])
        PhotoLibraryIndex.shared.requestAccess { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.titleLabel.text = "Photos are off for FavCircles"
                self.bodyLabel.text = "To find the places in your photos, allow FavCircles to see your photos in Settings."
                self.primaryButton.setTitle("Open Settings", for: .normal)
                self.primaryButton.removeTarget(self, action: #selector(self.start), for: .touchUpInside)
                self.primaryButton.addTarget(self, action: #selector(self.openSettings), for: .touchUpInside)
                return
            }
            self.scan()
        }
    }

    @objc private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    private func scan() {
        primaryButton.isEnabled = false
        primaryButton.setTitle("Looking through your photos\u{2026}", for: .normal)
        let group = DispatchGroup()
        var current: CLLocationCoordinate2D?
        var shots: [PhotoLibraryMath.Shot] = []
        group.enter()
        LocationService.shared.recentLocation(timeout: 3) { location in
            current = location?.coordinate
            group.leave()
        }
        group.enter()
        PhotoLibraryIndex.shared.shots { all in
            shots = all
            group.leave()
        }
        let saved = savedPlaces.compactMap { $0.location?.clLocation?.coordinate }
        let done = PhotoMapProgressStore.done(uid: uid)
        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            let spots = PhotoFindSpot.fromLibrary(shots, saved: saved, done: done, nearestTo: current, nearestFirst: true)
            DispatchQueue.main.async {
                guard let self else { return }
                self.primaryButton.isEnabled = true
                self.primaryButton.setTitle("Build my map", for: .normal)
                AnalyticsService.shared.logEvent("photo_map_scanned", parameters: ["photos": String(shots.count), "spots": String(spots.count)])
                AnalyticsService.shared.logEvent("photo_map_accuracy",
                                                 parameters: PhotoLibraryMath.accuracyReport(shots: shots, spotUncertainties: spots.map(\.uncertainty)))
                guard !spots.isEmpty else {
                    return self.showError("No new places in your photos: they were taken at home, at places you\u{2019}ve already saved, or without a location.")
                }
                let finder = PhotoPlaceFinder(spots: spots)
                // Near places first; the review page offers Keep looking
                finder.pauseAfterFinds = 40
                let review = PhotoPlacesReviewViewController(finder: finder, circles: self.circles, target: .photos, title: "Build my map")
                review.onFinished = self.onFinished
                self.navigationController?.pushViewController(review, animated: true)
            }
        }
    }

    @objc private func close() {
        AnalyticsService.shared.logEvent("photo_map_skipped", parameters: [:])
        if let onFinished { return onFinished() }
        navigationController?.popViewController(animated: true)
    }
}

/// Sign-up step after Location (Wes, 2026-10-16: offer it to new users):
/// "Build your map from your photos" / Not now.
final class PhotoMapOnboardingViewController: PermissionPrimerViewController {
    override var symbolName: String { "photo.stack.fill" }
    /// The place they just saved as their first favorite, when they did:
    /// the offer is about more places like it (2026-10-31)
    var favoritePlaceName: String?
    override var headline: String { FirstFavoriteCopy.photoMapHeadline(placeName: favoritePlaceName) }
    override var subheadline: String { FirstFavoriteCopy.photoMapSubheadline(placeName: favoritePlaceName) }
    override var reasons: [Reason] {
        [Reason(symbol: "mappin.and.ellipse", title: "Places near you first",
                detail: "Coffee shops, restaurants, parks: the spots you've photographed around home."),
         Reason(symbol: "lock.fill", title: "Your photos stay on your phone",
                detail: "We only read where they were taken. One photo per place is added."),
         Reason(symbol: "eye.slash", title: "Switch them off any time",
                detail: "They go in their own circle, \u{201C}Places from my photos.\u{201D}")]
    }
    override var footnote: String? { "Your first 25 places are free." }
    override var allowTitle: String { "Build my map" }

    /// Shown once per install, only when the photo library hasn't been
    /// read yet.
    static var isNeeded: Bool {
        !UserDefaults.standard.bool(forKey: "hasShownPhotoMapOnboarding")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        UserDefaults.standard.set(true, forKey: "hasShownPhotoMapOnboarding")
    }

    override func requestPermission() {
        AnalyticsService.shared.logEvent("onboarding_photo_map", parameters: ["answer": "build"])
        let builder = PhotoMapBuilderViewController(savedPlaces: [], circles: [], startsImmediately: true)
        builder.onFinished = { [weak self] in self?.finish() }
        builder.navigationItem.hidesBackButton = true
        navigationController?.pushViewController(builder, animated: true)
    }
}
