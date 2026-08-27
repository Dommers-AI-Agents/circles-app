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
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []

        // Map apps often put the place NAME only in the item's attributed
        // title/content ("Office Depot · Charlotte") and attach just a URL —
        // capture both as text fallbacks.
        for item in items {
            if sharedText == nil, let text = item.attributedContentText?.string, !text.isEmpty {
                sharedText = text
            }
            if sharedText == nil, let title = item.attributedTitle?.string, !title.isEmpty {
                sharedText = title
            }
        }

        let providers = items.flatMap { $0.attachments ?? [] }
        let group = DispatchGroup()
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                    // URL arrives as NSURL, String, or Data depending on the host app
                    if let url = item as? URL {
                        self?.sharedURL = url.absoluteString
                    } else if let text = item as? String {
                        self?.sharedURL = text
                    } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                        self?.sharedURL = text
                    }
                    group.leave()
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                    if let text = item as? String, !text.isEmpty { self?.sharedText = text }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    // MARK: Resolution

    private struct URLHints {
        var name: String?
        var coordinate: CLLocationCoordinate2D?
        var isEmpty: Bool { name == nil && coordinate == nil }
    }

    /// Pulls a place name and/or coordinate out of a Google or Apple Maps URL.
    private static func placeHints(from urlString: String) -> URLHints {
        var hints = URLHints()

        if ImportParsingService.isGoogleMapsURL(urlString) {
            if let pin = ImportParsingService.pinCoordinates(fromGoogleURL: urlString)
                ?? ImportParsingService.featureCoordinate(fromGoogleURL: urlString) {
                hints.coordinate = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
            }
            // Long-form place URLs carry the name: /maps/place/Office+Depot/@35.2,-80.8...
            if let range = urlString.range(of: #"/maps/place/([^/@?]+)"#, options: .regularExpression) {
                let raw = String(urlString[range].dropFirst("/maps/place/".count))
                let name = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? raw
                if !name.isEmpty { hints.name = name }
            }
            // The @lat,lng viewport centroid is a usable region hint when the
            // feature id is absent (mobile share links after redirect)
            if hints.coordinate == nil,
               let range = urlString.range(of: #"@(-?\d+\.\d+),(-?\d+\.\d+)"#, options: .regularExpression) {
                let parts = String(urlString[range].dropFirst()).components(separatedBy: ",")
                if parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]),
                   abs(lat) <= 90, abs(lng) <= 180 {
                    hints.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
            }
            return hints
        }

        // Apple Maps: https://maps.apple.com/?q=Office+Depot&ll=35.22,-80.84&address=...
        if urlString.lowercased().contains("maps.apple") {
            guard let components = URLComponents(string: urlString) else { return hints }
            let items = components.queryItems ?? []
            let value = { (key: String) in items.first(where: { $0.name == key })?.value }
            for key in ["name", "q", "address"] {
                if let v = value(key), !v.isEmpty, Double(v.components(separatedBy: ",").first ?? "") == nil {
                    hints.name = v.replacingOccurrences(of: "+", with: " ")
                    break
                }
            }
            for key in ["ll", "sll", "center", "coordinate"] {
                if let v = value(key) {
                    let parts = v.components(separatedBy: ",")
                    if parts.count == 2,
                       let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                       let lng = Double(parts[1].trimmingCharacters(in: .whitespaces)),
                       abs(lat) <= 90, abs(lng) <= 180 {
                        hints.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                        break
                    }
                }
            }
            return hints
        }

        return hints
    }

    /// Share links from the Maps apps are redirectors (maps.app.goo.gl,
    /// maps.apple/p/…) — the name and coordinates only exist on the URL they
    /// redirect to. One GET resolves it; the final URL is what we parse.
    private func resolveFinalURL(_ urlString: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: urlString) else { completion(urlString); return }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                completion(response?.url?.absoluteString ?? urlString)
            }
        }.resume()
    }

    private func startResolution() {
        // Some apps put the URL inside the text ("Check out X!
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
        // Share-sheet titles look like "Office Depot · Charlotte, North..." —
        // keep the name half, drop the truncated location tail.
        if let dotRange = seedName.range(of: " · ") {
            seedName = String(seedName[..<dotRange.lowerBound])
        }
        seedName = seedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "!·-–:"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        placeNameLabel.text = seedName.isEmpty ? "Locating…" : seedName
        spinner.startAnimating()

        let hints = sharedURL.map(Self.placeHints(from:)) ?? URLHints()
        if hints.coordinate == nil, let urlString = sharedURL, URL(string: urlString) != nil {
            // Nothing useful in the URL as shared — follow its redirect and
            // parse what it lands on (short links from both Maps apps).
            resolveFinalURL(urlString) { [weak self] finalURL in
                let resolved = Self.placeHints(from: finalURL)
                self?.continueResolution(seedName: seedName,
                                         name: resolved.name ?? hints.name,
                                         coordinate: resolved.coordinate)
            }
        } else {
            continueResolution(seedName: seedName, name: hints.name, coordinate: hints.coordinate)
        }
    }

    private func continueResolution(seedName: String, name: String?, coordinate: CLLocationCoordinate2D?) {
        let seedName = seedName.isEmpty ? (name ?? "") : seedName

        guard !seedName.isEmpty || coordinate != nil else {
            spinner.stopAnimating()
            showParkAndFinish(message: "Couldn't read a place from this share")
            return
        }

        if !seedName.isEmpty { placeNameLabel.text = seedName }

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
