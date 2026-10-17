import UIKit
import MapKit
import CoreLocation

/// "Build my map from my photos" (Wes, 2026-10-16): reads where the user's
/// photos were taken, finds the business at each spot with Apple Maps (free,
/// on the phone), and adds them automatically to "Places from my photos",
/// nearest first so the free 25 are their own neighborhood. Then Premium for
/// the rest. The circle and its places can be switched off the map (circle
/// switch, or My Places + → From your photos).
final class PhotoMapBuilderViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private enum Phase { case intro, denied, scanning, working, limit, failed, done }

    private let savedPlaces: [Place]
    private let startsImmediately: Bool
    /// Set by the sign-up step: "See my map" ends the step instead
    var onFinished: (() -> Void)?

    private var phase: Phase = .intro
    private var queue: [PhotoLibraryMath.Spot] = []
    private var index = 0
    private var pending: [PhotoMapPlace] = []
    private var noMatchKeys: [String] = []
    private var added = 0
    private var remainingFree: Int?
    private var circleId: String?
    private var stopped = false
    private var recentNames: [String] = []
    private var uid: String { AuthService.shared.getUserId() ?? "anon" }

    private let iconView = UIImageView(image: UIImage(systemName: "photo.stack.fill"))
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let statusLabel = UILabel()
    private let namesLabel = UILabel()
    private lazy var primaryButton = UIButton.primaryButton(title: "Build my map")
    private lazy var secondaryButton = UIButton.secondaryButton(title: "Not now")

    init(savedPlaces: [Place], startsImmediately: Bool = false) {
        self.savedPlaces = savedPlaces
        self.startsImmediately = startsImmediately
        super.init(nibName: nil, bundle: nil)
        title = "From my photos"
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
        bodyLabel.font = .systemFont(ofSize: 16)
        bodyLabel.textColor = Constants.Colors.secondaryLabel
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        progressView.progressTintColor = Constants.Colors.primary
        progressView.layer.cornerRadius = 3
        progressView.clipsToBounds = true
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = Constants.Colors.secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        namesLabel.font = .systemFont(ofSize: 15)
        namesLabel.textColor = Constants.Colors.label
        namesLabel.textAlignment = .center
        namesLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, bodyLabel, progressView, statusLabel, namesLabel, UIView(), primaryButton, secondaryButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(24, after: bodyLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 64),
            progressView.heightAnchor.constraint(equalToConstant: 6),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
        render()
        if startsImmediately { start() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Back from the paywall with Premium: pick up where it stopped
        if phase == .limit, SubscriptionManager.shared.isSubscribed {
            resume()
        }
    }

    // MARK: - Screen

    private func render() {
        progressView.isHidden = !(phase == .working || phase == .limit || phase == .done)
        statusLabel.isHidden = phase == .intro
        namesLabel.isHidden = recentNames.isEmpty || phase == .intro
        namesLabel.text = recentNames.prefix(5).joined(separator: "\n")
        secondaryButton.isHidden = false
        primaryButton.isEnabled = true
        if !queue.isEmpty { progressView.progress = Float(index) / Float(queue.count) }

        switch phase {
        case .intro:
            titleLabel.text = "Build your map from your photos"
            bodyLabel.text = "We look at where your photos were taken, find the places, and add them to a circle called \u{201C}Places from my photos.\u{201D} Places near you come first. Your first 25 are free.\n\nYour photos stay on your phone; only one photo per place is added, and you can switch these places off your map any time."
            primaryButton.setTitle("Build my map", for: .normal)
            secondaryButton.setTitle("Not now", for: .normal)
        case .denied:
            titleLabel.text = "Photos are off for FavCircles"
            bodyLabel.text = "To find the places in your photos, allow FavCircles to see your photos in Settings."
            primaryButton.setTitle("Open Settings", for: .normal)
            secondaryButton.setTitle("Not now", for: .normal)
        case .scanning:
            titleLabel.text = "Looking through your photos"
            bodyLabel.text = "Starting with places near you."
            statusLabel.text = "Reading where your photos were taken\u{2026}"
            primaryButton.setTitle("Working\u{2026}", for: .normal)
            primaryButton.isEnabled = false
            secondaryButton.setTitle("Cancel", for: .normal)
        case .working:
            titleLabel.text = "Adding places to your map"
            bodyLabel.text = "Places near you first."
            statusLabel.text = PhotoMapPlanner.progressLine(added: added, checked: index, total: queue.count)
            primaryButton.setTitle("Stop", for: .normal)
            secondaryButton.isHidden = true
        case .limit:
            titleLabel.text = "Your map is filling in"
            let more = max(0, queue.count - index) + pending.count
            bodyLabel.text = PhotoMapPlanner.limitLine(added: added, freeMax: 25, more: more)
            statusLabel.text = PhotoMapPlanner.progressLine(added: added, checked: index, total: queue.count)
            primaryButton.setTitle("Add the rest with Premium", for: .normal)
            secondaryButton.setTitle("See my map", for: .normal)
        case .failed:
            titleLabel.text = "We couldn\u{2019}t reach FavCircles"
            bodyLabel.text = "Check your connection and try again. Nothing found so far is lost."
            primaryButton.setTitle("Try again", for: .normal)
            secondaryButton.setTitle("Not now", for: .normal)
        case .done:
            titleLabel.text = added > 0 ? "Your map is ready" : "All caught up"
            bodyLabel.text = PhotoMapPlanner.doneLine(added: added)
            statusLabel.text = added > 0 ? "Turn them off the map any time: the circle\u{2019}s switch, or My Places + on the map." : nil
            primaryButton.setTitle("See my map", for: .normal)
            secondaryButton.setTitle("Open the circle", for: .normal)
            secondaryButton.isHidden = circleId == nil
        }
    }

    @objc private func primaryTapped() {
        switch phase {
        case .intro: start()
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .scanning: break
        case .working:
            stopped = true
            flush { [weak self] in self?.finish() }
        case .limit:
            AnalyticsService.shared.logEvent("photo_map_paywall_opened", parameters: ["added": String(added)])
            SubscriptionManager.shared.showPaywall(from: self, reason: .photoPlaces)
        case .failed: resume()
        case .done: seeMyMap()
        }
    }

    @objc private func secondaryTapped() {
        switch phase {
        case .intro, .denied, .failed, .scanning:
            stopped = true
            AnalyticsService.shared.logEvent("photo_map_skipped", parameters: ["phase": "\(phase)"])
            close()
        case .limit: seeMyMap()
        case .done: openCircle()
        case .working: break
        }
    }

    // MARK: - Scan

    private func start() {
        AnalyticsService.shared.logEvent("photo_map_started", parameters: [:])
        PhotoLibraryIndex.shared.requestAccess { [weak self] granted in
            guard let self else { return }
            guard granted else { self.phase = .denied; self.render(); return }
            self.phase = .scanning
            self.render()
            self.scan()
        }
    }

    private func scan() {
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
            let ordered = shots.sorted { $0.date < $1.date }
            let home = PhotoLibraryMath.home(ordered)
            let spots = PhotoMapPlanner.candidates(PhotoLibraryMath.spots(ordered), home: home, saved: saved, done: done)
            let queue = PhotoMapPlanner.ordered(spots, origin: PhotoMapPlanner.origin(current: current, home: home))
            DispatchQueue.main.async {
                guard let self, !self.stopped else { return }
                self.queue = queue
                self.index = 0
                AnalyticsService.shared.logEvent("photo_map_scanned", parameters: ["photos": String(shots.count), "spots": String(queue.count)])
                self.phase = .working
                self.render()
                self.next()
            }
        }
    }

    /// One spot at a time, paced for Apple's lookup limit (~50 a minute).
    private func next() {
        guard !stopped else { return }
        if let remaining = remainingFree {
            if remaining == 0 { return reachLimit() }
            // Enough for what's left of the free allowance: send (the reply
            // ends at the limit)
            if pending.count >= remaining { return send() }
        }
        guard index < queue.count else {
            return flush { [weak self] in self?.finish() }
        }
        let spot = queue[index]
        let started = Date()
        let key = PhotoMapPlanner.key(spot)
        NearbyPOILookup.pointsOfInterest(near: spot.center, radius: PhotoPlaceRanker.poiRadiusMeters) { [weak self] items in
            guard let self, !self.stopped else { return }
            self.index += 1
            let pace = max(0, 1.2 - Date().timeIntervalSince(started))
            guard let item = items.first(where: { !AppleMapItemFormFill.isResidentialAddress(name: $0.name) }),
                  let name = item.name else {
                self.noMatchKeys.append(key)
                self.render()
                DispatchQueue.main.asyncAfter(deadline: .now() + pace) { self.next() }
                return
            }
            self.photoUrl(for: spot) { url in
                let mapping = AppleMapItemFormFill.categoryMapping(poiCategory: item.pointOfInterestCategory, name: name)
                self.pending.append(PhotoMapPlace(
                    name: name, address: Self.address(item.placemark), coordinate: item.placemark.coordinate,
                    category: mapping.category.rawValue, applePoiCategory: item.pointOfInterestCategory?.rawValue,
                    photoUrl: url, spotKey: key))
                self.recentNames.insert(name, at: 0)
                self.render()
                let full = self.pending.count >= PhotoMapPlanner.batchSize
                    || (self.remainingFree.map { self.pending.count >= $0 } ?? false)
                if full {
                    self.send()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + pace) { self.next() }
                }
            }
        }
    }

    /// The spot's middle photo, uploaded (re-encoded, no GPS in it).
    private func photoUrl(for spot: PhotoLibraryMath.Spot, completion: @escaping (String?) -> Void) {
        let shot = spot.shots[spot.shots.count / 2]
        PhotoLibraryIndex.shared.uploadImage(for: shot.id) { image in
            guard let data = image?.jpegData(compressionQuality: 0.8) else { return completion(nil) }
            PlaceService.shared.uploadImage(data) { result in
                DispatchQueue.main.async { completion(try? result.get()) }
            }
        }
    }

    private func send(continueAfter: Bool = true) {
        let batch = pending
        guard !batch.isEmpty else {
            PhotoMapProgressStore.markDone(noMatchKeys, uid: uid)
            noMatchKeys = []
            if continueAfter { next() }
            return
        }
        PhotoMapService.add(batch) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .added(let result):
                self.circleId = result.circleId ?? self.circleId
                self.remainingFree = result.remainingFree
                let accepted = result.upgradeRequired == true
                    ? min(batch.count, result.added + (result.skippedDuplicates ?? 0))
                    : batch.count
                self.added += result.added
                PhotoMapProgressStore.markDone(batch.prefix(accepted).map(\.spotKey) + self.noMatchKeys, uid: self.uid)
                self.noMatchKeys = []
                self.pending = Array(batch.dropFirst(accepted))
                if result.added > 0 {
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
                }
                if result.upgradeRequired == true || self.remainingFree == 0 {
                    self.reachLimit()
                } else if continueAfter {
                    self.render()
                    self.next()
                }
            case .limitReached:
                self.remainingFree = 0
                self.reachLimit()
            case .failed:
                self.phase = .failed
                self.render()
            }
        }
    }

    /// Sends what's waiting (Stop, end of the queue), then `completion`.
    private func flush(_ completion: @escaping () -> Void) {
        guard !pending.isEmpty else {
            PhotoMapProgressStore.markDone(noMatchKeys, uid: uid)
            noMatchKeys = []
            return completion()
        }
        PhotoMapService.add(pending) { [weak self] outcome in
            guard let self else { return }
            if case .added(let result) = outcome {
                self.added += result.added
                self.circleId = result.circleId ?? self.circleId
                PhotoMapProgressStore.markDone(self.pending.map(\.spotKey) + self.noMatchKeys, uid: self.uid)
                self.pending = []
                self.noMatchKeys = []
                NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
                if result.upgradeRequired == true { return self.reachLimit() }
            } else if case .limitReached = outcome {
                return self.reachLimit()
            }
            completion()
        }
    }

    private func reachLimit() {
        AnalyticsService.shared.logEvent("photo_map_limit", parameters: ["added": String(added), "left": String(queue.count - index)])
        phase = .limit
        render()
    }

    private func resume() {
        stopped = false
        remainingFree = SubscriptionManager.shared.isSubscribed ? nil : remainingFree
        phase = queue.isEmpty ? .scanning : .working
        render()
        if queue.isEmpty { scan() } else { send() }
    }

    private func finish() {
        AnalyticsService.shared.logEvent("photo_map_finished", parameters: ["added": String(added)])
        phase = .done
        render()
    }

    // MARK: - Leaving

    private func seeMyMap() {
        NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
        if let onFinished { return onFinished() }
        tabBarController?.selectedIndex = 0
        navigationController?.popToRootViewController(animated: true)
    }

    private func openCircle() {
        guard let circleId else { return seeMyMap() }
        CircleService.shared.fetchCircleById(id: circleId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success(let circle) = result else { return self.seeMyMap() }
                if let onFinished = self.onFinished {
                    onFinished()
                    return
                }
                let detail = CircleDetailViewController(circle: circle)
                var stack = self.navigationController?.viewControllers ?? []
                stack.removeAll { $0 === self }
                stack.append(detail)
                self.navigationController?.setViewControllers(stack, animated: true)
            }
        }
    }

    private func close() {
        if let onFinished { return onFinished() }
        if navigationController?.viewControllers.first === self {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private static func address(_ p: MKPlacemark) -> String {
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, p.locality, p.administrativeArea, p.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Sign-up step after Location (Wes, 2026-10-16: offer it to new users):
/// "Build your map from your photos" / Not now.
final class PhotoMapOnboardingViewController: PermissionPrimerViewController {
    override var symbolName: String { "photo.stack.fill" }
    override var headline: String { "Fill your map from your photos" }
    override var subheadline: String { "The places you've already been are in your camera roll. We'll put them on your map." }
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
        let builder = PhotoMapBuilderViewController(savedPlaces: [], startsImmediately: true)
        builder.onFinished = { [weak self] in self?.finish() }
        builder.navigationItem.hidesBackButton = true
        navigationController?.pushViewController(builder, animated: true)
    }
}
