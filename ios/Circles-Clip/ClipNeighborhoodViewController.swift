import CoreLocation
import UIKit

/// Step 1: where they live (2026-11-24). At a store: "Is this your
/// neighborhood?" — one tap, and the store's spot gives the zip (no location
/// prompt, no address). Otherwise, or on "Enter my zip instead", a zip field.
/// The zip goes on the profile (PUT users/me), which centers their map and
/// finds people nearby. Just a zip, never an address.
final class ClipNeighborhoodViewController: ClipStepViewController, UITextFieldDelegate {
    private let whyLabel = ClipTheme.label(.systemFont(ofSize: 15), color: UIColor.white.withAlphaComponent(0.8))
    private let zipField = ClipTheme.field(placeholder: "Your zip code", contentType: .postalCode)
    private let zipButton = ClipTheme.glassButton("Enter my zip instead")
    private let doneLabel = ClipTheme.label(.systemFont(ofSize: 17, weight: .semibold), color: ClipTheme.gold)
    private let geocoder = CLGeocoder()
    private var zipFieldShown = false
    private var busy = false

    init(flow: ClipOnboardingFlow) {
        super.init(flow: flow, step: .neighborhood, primary: flow.store?.coordinate != nil ? "Yes, I live near here" : "Continue")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let storeName = flow.store?.name
        if flow.store?.coordinate != nil, let storeName {
            hookLabel.attributedText = ClipTheme.hookText("Is this your", "neighborhood?", size: 44)
            detailLabel.text = "Your zip centers your map on home and finds people nearby who save places like \(storeName)."
        } else {
            hookLabel.attributedText = ClipTheme.hookText("Where's home?", "Your map starts there.", size: 44)
            detailLabel.text = "Your zip centers your map and finds people nearby who save the places you'd love."
        }
        whyLabel.text = "Just a zip, never your address. It's what makes \"nearby\" mean your streets, not the whole city."
        ClipTheme.lift(whyLabel)
        ClipTheme.lift(doneLabel)
        doneLabel.isHidden = true

        zipField.keyboardType = .numberPad
        zipField.delegate = self
        zipField.accessibilityIdentifier = "clipZip"
        zipField.addTarget(self, action: #selector(zipChanged), for: .editingChanged)
        zipButton.addTarget(self, action: #selector(zipTapped), for: .touchUpInside)

        [whyLabel, doneLabel, errorLabel, zipField, zipButton].forEach { stack.addArrangedSubview($0) }
        stack.setCustomSpacing(18, after: whyLabel)
        stack.setCustomSpacing(14, after: doneLabel)
        stack.setCustomSpacing(10, after: errorLabel)

        if flow.store?.coordinate == nil {
            showZipField(animated: false)
            ClipTheme.animateIn([stepLabel, hookLabel, detailLabel, whyLabel, zipField, primaryButton])
        } else {
            zipField.isHidden = true
            ClipTheme.animateIn([stepLabel, hookLabel, detailLabel, whyLabel, zipButton, primaryButton])
        }
        #if DEBUG
        ClipAutopilot.shared?.ready(self)
        #endif
    }

    // MARK: - Actions

    @objc private func zipTapped() {
        showZipField(animated: true)
        zipField.becomeFirstResponder()
    }

    private func showZipField(animated: Bool) {
        zipFieldShown = true
        zipField.isHidden = false
        zipButton.isHidden = true
        setPrimaryTitle("Continue")
        setPrimaryEnabled(Self.isZip(zipField.text))
        if animated { ClipTheme.animateIn([zipField]) }
    }

    @objc private func zipChanged() {
        let digits = (zipField.text ?? "").filter(\.isNumber)
        if zipField.text != digits { zipField.text = String(digits.prefix(5)) }
        hideError()
        setPrimaryEnabled(Self.isZip(zipField.text))
    }

    static func isZip(_ text: String?) -> Bool {
        (text ?? "").range(of: "^[0-9]{5}$", options: .regularExpression) != nil
    }

    override func primaryTapped() {
        guard !busy else { return }
        hideError()
        if zipFieldShown {
            guard Self.isZip(zipField.text), let zip = zipField.text else {
                showError("Enter your 5-digit zip code.")
                return
            }
            view.endEditing(true)
            setBusy(true)
            Task { @MainActor in
                // The zip's spot, for "near you" and the city on screen
                let placemark = try? await geocoder.geocodeAddressString(zip).first
                await apply(zip: zip, placemark: placemark)
            }
        } else if let spot = flow.store?.coordinate {
            setBusy(true)
            Task { @MainActor in
                let location = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
                let placemark = try? await geocoder.reverseGeocodeLocation(location).first
                if let zip = placemark?.postalCode, Self.isZip(zip) {
                    await apply(zip: zip, placemark: placemark)
                } else {
                    // Couldn't read the store's zip: ask for it
                    setBusy(false)
                    showZipField(animated: true)
                    zipField.becomeFirstResponder()
                }
            }
        }
    }

    /// Saves the zip on the profile, then on
    private func apply(zip: String, placemark: CLPlacemark?) async {
        do {
            try await ClipAPIClient.shared.updateZipcode(zip, bearer: flow.session.token)
        } catch ClipAPIError.unauthorized {
            setBusy(false)
            showError("Please sign in again.")
            return
        } catch {
            setBusy(false)
            showError(error.localizedDescription)
            return
        }
        let city = [placemark?.locality, placemark?.administrativeArea].compactMap { $0 }.joined(separator: ", ")
        if flow.origin == nil, let spot = placemark?.location?.coordinate, CLLocationCoordinate2DIsValid(spot) {
            flow.origin = spot
        }
        flow.record { s in
            s.zipcodeSet = true
            s.city = city.isEmpty ? nil : city
        }
        flow.complete(.neighborhood)
        setBusy(false)
        doneLabel.text = city.isEmpty ? "Saved ✓  Your map is centered." : "\(city) ✓  Your map is centered."
        doneLabel.isHidden = false
        zipField.isHidden = true
        zipButton.isHidden = true
        setPrimaryEnabled(false)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in self?.advance() }
    }

    private func setBusy(_ on: Bool) {
        busy = on
        setPrimaryBusy(on)
        zipButton.isEnabled = !on
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        primaryTapped()
        return true
    }
}
