import UIKit
import MapKit
import UniformTypeIdentifiers

/// "Save to FavCircles" from the share sheet — Google Maps links, Safari
/// pages, copied text. The place is resolved on-device (Google-URL coordinate
/// extraction + Apple Maps search) and saved through the normal POST /places
/// path, so venue linking and FavCoin credit behave exactly like an in-app
/// add. No session or no network → the share parks in the App Group mailbox
/// and the main app finishes it on next launch.
final class ShareViewController: UIViewController {

    // MARK: State

    private var sharedURL: String?
    private var sharedText: String?

    private var resolvedName: String?
    private var resolvedAddress: String?
    private var resolvedCoordinate: CLLocationCoordinate2D?
    private var resolvedCategory = "other"

    private var client: ShareAPIClient?
    private var circles: [ShareAPIClient.CircleChoice] = []
    private var selectedCircle: ShareAPIClient.CircleChoice?

    private static let lastCircleKey = "shareExt.lastCircleId"
    private let groupDefaults = UserDefaults(suiteName: ExtensionAuthMailbox.appGroupId)

    // MARK: UI

    private let card = UIView()
    private let titleLabel = UILabel()
    private let placeNameLabel = UILabel()
    private let addressLabel = UILabel()
    private let circleButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        buildCard()

        client = ShareAPIClient.fromMailbox()
        extractSharedItem { [weak self] in
            self?.startResolution()
        }
    }

    // MARK: Shared item extraction

    private func extractSharedItem(completion: @escaping () -> Void) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        let group = DispatchGroup()
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                    if let url = item as? URL { self?.sharedURL = url.absoluteString }
                    group.leave()
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                    if let text = item as? String { self?.sharedText = text }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    // MARK: Resolution

    private func startResolution() {
        // Google Maps shares put the URL inside the text ("Check out X!
        // https://maps.app.goo.gl/..."); split it so the name survives.
        if sharedURL == nil, let text = sharedText,
           let range = text.range(of: "https://", options: .caseInsensitive) {
            sharedURL = String(text[range.lowerBound...])
                .components(separatedBy: .whitespacesAndNewlines).first
        }
        var seedName = sharedText ?? ""
        if let url = sharedURL, let range = seedName.range(of: url) {
            seedName.removeSubrange(range)
        }
        seedName = seedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "!·-–:"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var coordinate: CLLocationCoordinate2D?
        if let url = sharedURL, ImportParsingService.isGoogleMapsURL(url) {
            if let pin = ImportParsingService.pinCoordinates(fromGoogleURL: url)
                ?? ImportParsingService.featureCoordinate(fromGoogleURL: url) {
                coordinate = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
            }
        }

        guard !seedName.isEmpty || coordinate != nil else {
            showParkAndFinish(message: "Couldn't read a place from this share")
            return
        }

        placeNameLabel.text = seedName.isEmpty ? "Locating…" : seedName
        spinner.startAnimating()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = seedName.isEmpty ? "point of interest" : seedName
        if let coordinate = coordinate {
            request.region = MKCoordinateRegion(center: coordinate,
                                                latitudinalMeters: 800,
                                                longitudinalMeters: 800)
        }
        MKLocalSearch(request: request).start { [weak self] response, _ in
            guard let self = self else { return }
            self.spinner.stopAnimating()

            if let item = response?.mapItems.first {
                self.resolvedName = item.name ?? seedName
                self.resolvedAddress = Self.formatAddress(item.placemark)
                self.resolvedCoordinate = item.placemark.coordinate
                self.resolvedCategory = Self.category(for: item.pointOfInterestCategory)
            } else if let coordinate = coordinate, !seedName.isEmpty {
                // Apple couldn't match, but the Google URL gave us a pin —
                // save with the shared name at that spot.
                self.resolvedName = seedName
                self.resolvedAddress = "Address pending"
                self.resolvedCoordinate = coordinate
            } else {
                self.showParkAndFinish(message: "Couldn't find that place")
                return
            }

            self.placeNameLabel.text = self.resolvedName
            self.addressLabel.text = self.resolvedAddress
            self.loadCircles()
        }
    }

    private static func formatAddress(_ placemark: MKPlacemark) -> String {
        let parts = [
            [placemark.subThoroughfare, placemark.thoroughfare]
                .compactMap { $0 }.joined(separator: " "),
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode
        ].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? (placemark.title ?? "") : parts.joined(separator: ", ")
    }

    /// Compact Apple-POI → backend-category mapping (mirrors the app's
    /// AppleMapsService cascade for the categories a share is likely to hit).
    private static func category(for poi: MKPointOfInterestCategory?) -> String {
        guard let poi = poi else { return "other" }
        switch poi {
        case .restaurant, .bakery, .foodMarket: return "restaurant"
        case .cafe: return "cafe"
        case .brewery, .nightlife, .winery: return "bar"
        case .hotel: return "hotel"
        case .store, .pharmacy: return "retail"
        case .museum, .theater, .movieTheater, .amusementPark, .aquarium, .zoo: return "attraction"
        case .fitnessCenter: return "fitness"
        case .hospital: return "healthcare"
        case .school, .university, .library: return "education"
        case .park, .beach, .campground, .marina, .nationalPark: return "outdoor"
        case .airport, .carRental, .gasStation, .evCharger, .parking, .publicTransport: return "transport"
        case .bank, .atm: return "finance"
        case .stadium: return "entertainment"
        default: return "other"
        }
    }

    // MARK: Circles

    private func loadCircles() {
        guard let client = client else {
            // No session mirrored — park the share for the app to finish.
            parkPendingShare()
            showParkAndFinish(message: "Open FavCircles to finish saving")
            return
        }
        client.getCircles { [weak self] circles in
            guard let self = self else { return }
            self.circles = circles
            guard !circles.isEmpty else {
                self.parkPendingShare()
                self.showParkAndFinish(message: "Open FavCircles to finish saving")
                return
            }
            let lastUsedId = self.groupDefaults?.string(forKey: Self.lastCircleKey)
            self.selectedCircle = circles.first(where: { $0.id == lastUsedId }) ?? circles[0]
            self.refreshCircleButton()
            self.saveButton.isEnabled = true
        }
    }

    private func refreshCircleButton() {
        circleButton.setTitle("Circle: \(selectedCircle?.name ?? "…")  ▾", for: .normal)
        circleButton.menu = UIMenu(children: circles.map { choice in
            UIAction(title: choice.name,
                     state: choice.id == selectedCircle?.id ? .on : .off) { [weak self] _ in
                self?.selectedCircle = choice
                self?.refreshCircleButton()
            }
        })
        circleButton.showsMenuAsPrimaryAction = true
    }

    // MARK: Save

    @objc private func saveTapped() {
        guard let client = client,
              let name = resolvedName,
              let coordinate = resolvedCoordinate,
              let circle = selectedCircle else { return }

        saveButton.isEnabled = false
        spinner.startAnimating()
        groupDefaults?.set(circle.id, forKey: Self.lastCircleKey)

        client.createPlace(
            name: name,
            address: resolvedAddress ?? "Address pending",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: resolvedCategory,
            circleId: circle.id
        ) { [weak self] result in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            switch result {
            case .success(let coins):
                var message = "Saved to \(circle.name) ✓"
                if let coins = coins, coins > 0 {
                    message += "  +\(coins == coins.rounded() ? String(Int(coins)) : String(coins)) FavCoins"
                }
                self.titleLabel.text = message
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
            case .failure:
                // Offline or server hiccup: park it, the app finishes later.
                self.parkPendingShare()
                self.showParkAndFinish(message: "Saved for later — open FavCircles to finish")
            }
        }
    }

    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.favcircles.circles.Share", code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Cancelled"]))
    }

    private func parkPendingShare() {
        PendingShareMailbox.write(PendingShareMailbox.Payload(
            sharedURL: sharedURL,
            sharedText: resolvedName ?? sharedText,
            createdAt: Date()
        ))
    }

    private func showParkAndFinish(message: String) {
        titleLabel.text = message
        placeNameLabel.isHidden = placeNameLabel.text == nil
        saveButton.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    // MARK: Card layout (plain UIKit — the extension has no app design system)

    private func buildCard() {
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 16
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        titleLabel.text = "Save to FavCircles"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        placeNameLabel.font = .systemFont(ofSize: 16, weight: .medium)
        placeNameLabel.textAlignment = .center
        placeNameLabel.numberOfLines = 2

        addressLabel.font = .systemFont(ofSize: 13)
        addressLabel.textColor = .secondaryLabel
        addressLabel.textAlignment = .center
        addressLabel.numberOfLines = 2

        circleButton.titleLabel?.font = .systemFont(ofSize: 15)

        saveButton.setTitle("Save", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        saveButton.isEnabled = false
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, spinner, placeNameLabel, addressLabel, circleButton, saveButton, cancelButton
        ])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 300),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
    }
}
