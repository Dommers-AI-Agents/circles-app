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

    /// What this share looked like, dumped to the App Group container so a
    /// failed share can be diagnosed from the Mac (devicectl copy).
    private var debugInfo: [String: Any] = [:]

    private func dumpDebug() {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: ExtensionAuthMailbox.appGroupId)?
                .appendingPathComponent("share-debug.json"),
              JSONSerialization.isValidJSONObject(debugInfo),
              let data = try? JSONSerialization.data(withJSONObject: debugInfo, options: [.prettyPrinted]) else { return }
        try? data.write(to: url, options: [.atomic])
    }

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
        debugInfo["providerTypes"] = providers.map { $0.registeredTypeIdentifiers }
        debugInfo["attributedContent"] = items.compactMap { $0.attributedContentText?.string }
        debugInfo["attributedTitles"] = items.compactMap { $0.attributedTitle?.string }

        let group = DispatchGroup()
        for provider in providers {
            // Hosts register wildly different types ("public.url",
            // "public.plain-text", bare "public.text") and payload classes
            // (NSURL, NSString, Data) — try every text-ish type they claim.
            let urlTypes = [UTType.url.identifier, "public.file-url"]
            let textTypes = [UTType.plainText.identifier, "public.text", UTType.utf8PlainText.identifier]

            for type in urlTypes where provider.hasItemConformingToTypeIdentifier(type) {
                group.enter()
                provider.loadItem(forTypeIdentifier: type) { [weak self] item, _ in
                    self?.absorb(item, preferURL: true)
                    group.leave()
                }
                break
            }
            for type in textTypes where provider.hasItemConformingToTypeIdentifier(type) {
                group.enter()
                provider.loadItem(forTypeIdentifier: type) { [weak self] item, _ in
                    self?.absorb(item, preferURL: false)
                    group.leave()
                }
                break
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    /// Files any loaded payload into sharedURL/sharedText no matter how the
    /// host app encoded it.
    private func absorb(_ item: (any NSSecureCoding)?, preferURL: Bool) {
        var text: String?
        if let url = item as? URL {
            text = url.absoluteString
        } else if let string = item as? String {
            text = string
        } else if let data = item as? Data {
            text = String(data: data, encoding: .utf8)
        } else if let attributed = item as? NSAttributedString {
            text = attributed.string
        }
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }

        if value.lowercased().hasPrefix("http") && !value.contains(" ") {
            if sharedURL == nil { sharedURL = value }
        } else if preferURL, let range = value.range(of: "https://", options: .caseInsensitive) {
            // A "URL" payload that's actually prose with a link inside
            if sharedURL == nil {
                sharedURL = String(value[range.lowerBound...])
                    .components(separatedBy: .whitespacesAndNewlines).first
            }
            if sharedText == nil { sharedText = value }
        } else if sharedText == nil {
            sharedText = value
        }
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
            // Mobile/API links carry the feature id as ftid=0x...:0x... — same
            // S2 cell as the !1s form, different wrapper
            if hints.coordinate == nil,
               let match = firstMatch(#"ftid=0x([0-9a-fA-F]+):"#, in: urlString),
               let cell = ImportParsingService.s2CellCenter(hex: match) {
                hints.coordinate = CLLocationCoordinate2D(latitude: cell.lat, longitude: cell.lng)
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
            // ?q=Office+Depot (when it isn't a bare coordinate pair)
            if hints.name == nil,
               let q = URLComponents(string: urlString)?.queryItems?.first(where: { $0.name == "q" })?.value,
               !q.isEmpty, Double(q.components(separatedBy: ",").first ?? "") == nil {
                hints.name = q.replacingOccurrences(of: "+", with: " ")
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

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    private func firstMatch(_ pattern: String, in text: String) -> String? {
        Self.firstMatch(pattern, in: text)
    }

    /// Share links from the Maps apps are redirectors (maps.app.goo.gl,
    /// maps.apple/p/…) — the name and coordinates only exist past the
    /// redirect. One GET (with a desktop UA, so Google serves the full page
    /// instead of an open-in-app interstitial) yields BOTH the final URL and
    /// the page's og-tags: og:title carries the place name and og:image is a
    /// staticmap URL with center=lat,lng — a name+coordinate source that
    /// works even when the final URL itself is opaque.
    private func resolvePlacePage(_ urlString: String,
                                  completion: @escaping (_ finalURL: String,
                                                         _ pageName: String?,
                                                         _ pageCoordinate: CLLocationCoordinate2D?) -> Void) {
        guard let url = URL(string: urlString) else { completion(urlString, nil, nil); return }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            let finalURL = response?.url?.absoluteString ?? urlString
            var pageName: String?
            var pageCoordinate: CLLocationCoordinate2D?

            if let data = data, let html = String(data: data, encoding: .utf8) {
                if let title = Self.firstMatch(#"og:title"[^>]*content="([^"]+)""#, in: html)
                    ?? Self.firstMatch(#"content="([^"]+)"[^>]*og:title"#, in: html)
                    ?? Self.firstMatch(#"<title>([^<]+)</title>"#, in: html) {
                    let cleaned = title
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&#39;", with: "'")
                        .components(separatedBy: " - Google Maps").first?
                        .components(separatedBy: " · ").first?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let cleaned = cleaned, !cleaned.isEmpty,
                       !cleaned.lowercased().contains("google maps"),
                       !cleaned.lowercased().contains("apple maps") {
                        pageName = cleaned
                    }
                }
                // og:image staticmap: ...center=35.2271%2C-80.8431&zoom=...
                if let lat = Self.firstMatch(#"center=(-?\d+\.\d+)%2C-?\d+\.\d+"#, in: html),
                   let lng = Self.firstMatch(#"center=-?\d+\.\d+%2C(-?\d+\.\d+)"#, in: html),
                   let latValue = Double(lat), let lngValue = Double(lng),
                   abs(latValue) <= 90, abs(lngValue) <= 180 {
                    pageCoordinate = CLLocationCoordinate2D(latitude: latValue, longitude: lngValue)
                }
            }
            DispatchQueue.main.async { completion(finalURL, pageName, pageCoordinate) }
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

        debugInfo["sharedURL"] = sharedURL ?? "nil"
        debugInfo["sharedText"] = sharedText ?? "nil"
        debugInfo["seedName"] = seedName

        let hints = sharedURL.map(Self.placeHints(from:)) ?? URLHints()
        if hints.coordinate == nil, let urlString = sharedURL, URL(string: urlString) != nil {
            // Nothing useful in the URL as shared — follow its redirect and
            // mine the landing page (short links from both Maps apps).
            resolvePlacePage(urlString) { [weak self] finalURL, pageName, pageCoordinate in
                guard let self = self else { return }
                let resolved = Self.placeHints(from: finalURL)
                self.debugInfo["finalURL"] = finalURL
                self.debugInfo["pageName"] = pageName ?? "nil"
                self.debugInfo["pageCoordinate"] = pageCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? "nil"
                self.continueResolution(seedName: seedName,
                                        name: resolved.name ?? pageName ?? hints.name,
                                        coordinate: resolved.coordinate ?? pageCoordinate)
            }
        } else {
            continueResolution(seedName: seedName, name: hints.name, coordinate: hints.coordinate)
        }
    }

    private func continueResolution(seedName: String, name: String?, coordinate: CLLocationCoordinate2D?) {
        // A name mined from the URL/page beats a share-sheet title fragment
        let seedName = (name?.isEmpty == false ? name! : seedName)

        guard !seedName.isEmpty || coordinate != nil else {
            spinner.stopAnimating()
            debugInfo["outcome"] = "no_name_no_coordinate"
            dumpDebug()
            showParkAndFinish(message: "Couldn't read a place from this share")
            return
        }
        debugInfo["outcome"] = "searching: \(seedName)"
        dumpDebug()

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
