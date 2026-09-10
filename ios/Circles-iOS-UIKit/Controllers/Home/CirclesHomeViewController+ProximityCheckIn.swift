import UIKit
import CoreLocation

// The proximity check-in chip: when the app opens within ~50m of one of the
// user's saved places, a dismissible pill offers a one-tap check-in with the
// place pre-filled. Shown at most once per place per day; never during the
// first-session onboarding chain.
extension CirclesHomeViewController {

    private static let proximityRadiusMeters: CLLocationDistance = 50
    private static let chipTag = 99_431

    func maybeShowProximityCheckInChip() {
        guard view.viewWithTag(Self.chipTag) == nil,
              presentedViewController == nil,
              !OnboardingManager.shared.isFirstSessionFlowActive,
              [.authorizedWhenInUse, .authorizedAlways].contains(CLLocationManager().authorizationStatus),
              let userId = AuthService.shared.getUserId() else { return }

        LocationService.shared.getCurrentLocation { [weak self] location in
            guard let location = location else { return }
            PlacesDiskCache.shared.load(userId: userId) { [weak self] cached in
                guard let self = self, let places = cached, !places.isEmpty else { return }

                let nearest = places
                    .compactMap { place -> (Place, CLLocationDistance)? in
                        guard let placeLocation = place.location?.clLocation else { return nil }
                        return (place, location.distance(from: placeLocation))
                    }
                    .filter { $0.1 <= Self.proximityRadiusMeters }
                    .min { $0.1 < $1.1 }

                guard let (place, _) = nearest else { return }

                // Once per place per day
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "yyyy-MM-dd"
                let gateKey = "proximityCheckInPrompted.\(place.id).\(dayFormatter.string(from: Date()))"
                guard !UserDefaults.standard.bool(forKey: gateKey) else { return }
                UserDefaults.standard.set(true, forKey: gateKey)

                DispatchQueue.main.async { self.showProximityChip(for: place) }
            }
        }
    }

    private func showProximityChip(for place: Place) {
        guard view.viewWithTag(Self.chipTag) == nil else { return }

        let chip = UIControl()
        chip.tag = Self.chipTag
        chip.backgroundColor = Constants.Colors.primary
        chip.layer.cornerRadius = 22
        chip.layer.shadowColor = UIColor.black.cgColor
        chip.layer.shadowOpacity = 0.25
        chip.layer.shadowRadius = 8
        chip.layer.shadowOffset = CGSize(width: 0, height: 3)
        chip.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: .checkInIcon)
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "At \(place.name)?  Check in"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        label.translatesAutoresizingMaskIntoConstraints = false

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = UIColor.white.withAlphaComponent(0.8)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addAction(UIAction { [weak chip] _ in
            UIView.animate(withDuration: 0.2, animations: { chip?.alpha = 0 }) { _ in
                chip?.removeFromSuperview()
            }
        }, for: .touchUpInside)

        chip.addSubview(icon)
        chip.addSubview(label)
        chip.addSubview(close)
        view.addSubview(chip)

        NSLayoutConstraint.activate([
            chip.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            chip.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            chip.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            chip.heightAnchor.constraint(equalToConstant: 44),

            icon.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: chip.centerYAnchor),

            close.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            close.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 22),
        ])

        chip.addAction(UIAction { [weak self, weak chip] _ in
            guard let self = self else { return }
            chip?.removeFromSuperview()
            CheckInViewController.present(from: self, prefilledPlace: place)
        }, for: .touchUpInside)

        chip.alpha = 0
        chip.transform = CGAffineTransform(translationX: 0, y: -12)
        UIView.animate(withDuration: 0.3) {
            chip.alpha = 1
            chip.transform = .identity
        }

        // Quietly leave if ignored
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak chip] in
            guard let chip = chip, chip.superview != nil else { return }
            UIView.animate(withDuration: 0.3, animations: { chip.alpha = 0 }) { _ in
                chip.removeFromSuperview()
            }
        }
    }
}
