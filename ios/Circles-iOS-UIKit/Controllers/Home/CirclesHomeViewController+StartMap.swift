import UIKit

/// "Start your map" (new-user audit, 2026-10-09): until someone has saved a
/// place of their own (the onboarding example doesn't count), a small card
/// over the bottom of the map invites them to add their first few. The old
/// centred empty state only showed with no circles — never, since every
/// account starts with three — so the quick-start flow was unreachable.
extension CirclesHomeViewController {
    var hasOwnRealPlace: Bool {
        userOwnPlaces.contains { $0.isSamplePlace != true }
    }

    /// After the first-favorite step (2026-10-31): "You saved X. Add two
    /// more places you love." until they reach the quick-start goal. Only
    /// for people who saved a first favorite on this install.
    private var personalStartMapCopy: (title: String, body: String)? {
        guard let me = AuthService.shared.currentUser,
              let name = UserDefaults.standard.string(forKey: FirstFavoriteViewController.savedNameKey(me.id)) else { return nil }
        let count = userOwnPlaces.filter { $0.isSamplePlace != true }.count
        return FirstFavoriteCopy.homeCard(firstPlaceName: name, ownPlaceCount: count, goal: QuickStartAddPlacesViewController.goal)
    }

    func updateStartMapCard() {
        let personal = personalStartMapCopy
        let show = state.circlesLoaded && state.ownPlacesLoaded && !isLoadingPlaces && !isSearching && !startMapCardDismissed
            && AuthService.shared.currentUser != nil && (!hasOwnRealPlace || personal != nil)
        if show {
            if startMapCard == nil { installStartMapCard() }
            (startMapCard?.viewWithTag(Self.startMapTitleTag) as? UILabel)?.text = personal?.title ?? "Start your map 🗺️"
            (startMapCard?.viewWithTag(Self.startMapBodyTag) as? UILabel)?.text = personal?.body
                ?? "Save a few places you love — they become your personal map for friends to explore."
            startMapCard?.isHidden = false
        } else {
            startMapCard?.isHidden = true
        }
    }

    private static let startMapTitleTag = 7301
    private static let startMapBodyTag = 7302

    private func installStartMapCard() {
        let card = UIView()
        card.backgroundColor = Constants.Colors.background.withAlphaComponent(0.96)
        card.layer.cornerRadius = 16
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.18
        card.layer.shadowRadius = 10
        card.layer.shadowOffset = CGSize(width: 0, height: 3)
        card.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Start your map 🗺️"
        title.tag = Self.startMapTitleTag
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = Constants.Colors.label
        let body = UILabel()
        body.text = "Save a few places you love — they become your personal map for friends to explore."
        body.tag = Self.startMapBodyTag
        body.font = .systemFont(ofSize: 14)
        body.textColor = Constants.Colors.secondaryLabel
        body.numberOfLines = 0
        let add = UIButton.smallActionButton(title: "Add places", style: .primary)
        add.addTarget(self, action: #selector(startMapAddTapped), for: .touchUpInside)
        let close = UIButton.iconButton(systemName: "xmark", pointSize: 13)
        close.tintColor = Constants.Colors.secondaryLabel
        close.accessibilityLabel = "Hide"
        close.addTarget(self, action: #selector(startMapCloseTapped), for: .touchUpInside)

        let text = UIStackView(arrangedSubviews: [title, body])
        text.axis = .vertical
        text.spacing = 3
        for v in [text, add, close] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(v) }
        mapContainerView.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor, constant: -60),
            card.bottomAnchor.constraint(equalTo: mapContainerView.bottomAnchor, constant: -12),
            text.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            text.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            text.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -6),
            close.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),
            add.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 10),
            add.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            add.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        startMapCard = card
    }

    @objc private func startMapAddTapped() {
        AnalyticsService.shared.logEvent("start_map_card_tapped", parameters: [:])
        openQuickStartAddPlaces()
    }

    @objc private func startMapCloseTapped() {
        // Back next session until they've added one
        startMapCardDismissed = true
        updateStartMapCard()
    }
}
