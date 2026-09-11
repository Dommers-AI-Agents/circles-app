import UIKit
import CoreLocation

/// What a row in one of the map's filter dropdowns asks the controller to do.
enum MapFilterMenuAction {
    /// Everyone (nil), My Connections, or one person.
    case selectConnection(id: String?, user: User?)
    /// My Places with no origin sub-filter.
    case selectMyPlaces
    /// An origin sub-row under My Places ("in_app", "google_maps", …).
    case selectImportOrigin(String)
    case selectChipGroup(PlaceCategoryGroup)
    /// nil = All Places.
    case selectRegion(id: String?)
}

protocol MapFilterMenuBuilderDelegate: AnyObject {
    /// A fresh snapshot of the selections and data the menus are built from.
    func menuBuilderState(_ builder: MapFilterMenuBuilder) -> MapFilterMenuBuilder.State
    func menuBuilder(_ builder: MapFilterMenuBuilder, perform action: MapFilterMenuAction)
}

/// Builds the full-screen map's three header dropdowns — Connection,
/// Category, Place — and keeps the avatar cache warm so the people rows
/// show faces on first open. Menus are rebuilt fresh every time (the
/// controller wraps them in `UIDeferredMenuElement.uncached`), so every
/// build asks the delegate for the current state.
final class MapFilterMenuBuilder {
    struct State {
        var selectedConnectionId: String?
        var selectedImportOrigin: String?
        var selectedChipGroup: PlaceCategoryGroup = .all
        var selectedChipRegionId: String?
        var chipRegionGroups: [RegionGroup] = []
        /// Anchor for the "Near me" region row.
        var chipOrigin: CLLocation?
        /// Every place the map knows (for the origin sub-rows).
        var places: [Place] = []
        var connections: [Connection] = []
        /// Places under the current connection scope and origin filter — the
        /// base the category and region menus facet from.
        var facetBase: [Place] = []
    }

    weak var delegate: MapFilterMenuBuilderDelegate?

    private var state: State {
        delegate?.menuBuilderState(self) ?? State()
    }

    // MARK: - Connection menu

    /// Everyone / My Connections / My Places, then each person in the home
    /// connections row's order — the same ranking, so the list reads identically
    /// everywhere. Each person shows their avatar, so it scans by face not name.
    func connectionMenuElements() -> [UIMenuElement] {
        let state = self.state
        // "My Places" wears YOUR face — same circular treatment as everyone
        // below it, so the row reads as you rather than a generic glyph.
        let myAvatar: UIImage?
        if let me = AuthService.shared.currentUser {
            myAvatar = menuAvatar(for: me)
        } else {
            myAvatar = UIImage(systemName: "person.crop.circle.fill")?
                .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        }

        // "Everyone" gets a two-tone palette symbol — one figure in the
        // brand color, one in a warm accent — so it reads as "everyone", not
        // another flat glyph. Rasterized to pixels: withRenderingMode after
        // applyingSymbolConfiguration silently DROPS the palette, and menus
        // re-tint template images — baking the bitmap sidesteps both.
        let followingIcon: UIImage? = {
            guard let symbol = UIImage(
                systemName: "person.2.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
                    .applying(UIImage.SymbolConfiguration(paletteColors: [Constants.Colors.primary, .systemOrange]))
            ) else { return nil }
            return UIGraphicsImageRenderer(size: symbol.size).image { _ in
                symbol.draw(at: .zero)
            }.withRenderingMode(.alwaysOriginal)
        }()

        // "Everyone" (nil) leads the list — the default scope: you + your
        // accepted connections + everyone you follow.
        var actions: [UIAction] = [
            UIAction(title: "Everyone",
                     image: followingIcon,
                     state: state.selectedConnectionId == nil ? .on : .off) { [weak self] _ in
                self?.perform(.selectConnection(id: nil, user: nil))
            }
        ]

        // "My Connections" = accepted connections only (the narrower cut).
        let myConnectionsIcon = UIImage(
            systemName: "person.2.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        )?.withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        actions.append(
            UIAction(title: "My Connections",
                     image: myConnectionsIcon,
                     state: state.selectedConnectionId == HomePlaceFilter.myConnectionsOnlyId ? .on : .off) { [weak self] _ in
                self?.perform(.selectConnection(id: HomePlaceFilter.myConnectionsOnlyId, user: nil))
            }
        )

        actions.append(
            UIAction(title: "My Places",
                     image: myAvatar,
                     state: state.selectedConnectionId == HomePlaceFilter.myPlacesOnlyId && state.selectedImportOrigin == nil ? .on : .off) { [weak self] _ in
                self?.perform(.selectMyPlaces)
            }
        )

        // Origin sub-rows under My Places — only for users whose own places
        // include imports. Splits your pins into in-app adds vs each import
        // source ("was this from Google or added on FavCircles?").
        let currentUserIdForOrigins = AuthService.shared.getUserId() ?? ""
        let mySources = Set(state.places
            .filter { IDNormalizer.isSameUser($0.addedBy, currentUserIdForOrigins) }
            .compactMap { $0.importSource })
        if !mySources.isEmpty {
            var origins = ["in_app"] + mySources.sorted()
            // Keep the active selection pickable even if its places vanished
            if let active = state.selectedImportOrigin, !origins.contains(active) { origins.append(active) }
            for origin in origins {
                let icon = UIImage(systemName: origin == "in_app" ? "plus.app.fill" : "square.and.arrow.down.fill")?
                    .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
                actions.append(UIAction(
                    title: "›  \(MapChipFilter.originTitle(origin))",
                    image: icon,
                    state: state.selectedConnectionId == HomePlaceFilter.myPlacesOnlyId && state.selectedImportOrigin == origin ? .on : .off
                ) { [weak self] _ in
                    self?.perform(.selectImportOrigin(origin))
                })
            }
        }

        // Person rows: ranked connections first (same order as the home row),
        // then everyone else you follow — the map can scope to any of them.
        let currentUserId = AuthService.shared.getUserId() ?? ""
        var listedIds = Set<String>()
        for connection in HorizontalUserListView.rankedConnections(state.connections) {
            guard let user = connection.connectedUser else { continue }
            let otherId = connection.otherUserId(currentUserId: currentUserId)
            listedIds.insert(otherId)
            actions.append(UIAction(title: user.displayName,
                                    image: menuAvatar(for: user),
                                    state: state.selectedConnectionId == otherId ? .on : .off) { [weak self] _ in
                self?.perform(.selectConnection(id: otherId, user: user))
            })
        }
        for user in NetworkManager.shared.followingUsers {
            guard !user.id.isEmpty,
                  !listedIds.contains(user.id),
                  !IDNormalizer.isSameUser(user.id, currentUserId) else { continue }
            listedIds.insert(user.id)
            actions.append(UIAction(title: user.displayName,
                                    image: menuAvatar(for: user),
                                    state: state.selectedConnectionId == user.id ? .on : .off) { [weak self] _ in
                self?.perform(.selectConnection(id: user.id, user: user))
            })
        }
        return actions
    }

    // MARK: - Avatar warming

    /// Downloads every menu avatar that isn't already cached, then calls
    /// `completion` (on main). Capped so a dead network can't hold the menu
    /// hostage — anything still missing falls back to the placeholder.
    func withConnectionAvatarsWarmed(timeout: TimeInterval = 0.6, _ completion: @escaping () -> Void) {
        // The people list includes everyone followed — make sure that roster
        // is loaded before the menu builds (first open of the session)
        if NetworkManager.shared.followingUsers.isEmpty {
            NetworkManager.shared.loadFollowingUsers { [weak self] in
                self?.warmAvatars(timeout: timeout, completion)
            }
        } else {
            warmAvatars(timeout: timeout, completion)
        }
    }

    private func warmAvatars(timeout: TimeInterval, _ completion: @escaping () -> Void) {
        var users = state.connections.compactMap { $0.connectedUser }
        users.append(contentsOf: NetworkManager.shared.followingUsers)
        if let me = AuthService.shared.currentUser { users.append(me) }

        let pending: [(id: String, url: String)] = users.compactMap { user in
            guard let url = user.profilePicture, !url.isEmpty,
                  ImageService.shared.cachedImage(forKey: "profile_\(user.id)_\(url.hashValue)") == nil
            else { return nil }
            return (user.id, url)
        }
        guard !pending.isEmpty else { completion(); return }

        let group = DispatchGroup()
        pending.forEach { item in
            group.enter()
            ImageService.shared.loadProfileImage(for: item.id, from: item.url) { _ in group.leave() }
        }
        var finished = false
        let finish = { if !finished { finished = true; completion() } }
        group.notify(queue: .main) { finish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish() }
    }

    /// Circular avatar for a menu row, from the image cache. On a cache miss,
    /// returns a placeholder and prefetches so the NEXT open of this menu (it's
    /// rebuilt fresh every time via UIDeferredMenuElement) shows the photo.
    private func menuAvatar(for user: User) -> UIImage? {
        // No photo → a colored, filled avatar (never the flat grey glyph). The
        // hue is derived from the user id so a person keeps one color across
        // launches and the list reads as a row of distinct faces.
        let placeholder = Self.coloredAvatarPlaceholder(for: user)
        guard let urlString = user.profilePicture, !urlString.isEmpty else { return placeholder }

        let cacheKey = "profile_\(user.id)_\(urlString.hashValue)"
        if let cached = ImageService.shared.cachedImage(forKey: cacheKey) {
            return Self.circularMenuImage(cached)
        }
        // Warm the cache for the next open; menus can't be mutated in place.
        ImageService.shared.loadProfileImage(for: user.id, from: urlString) { _ in }
        return placeholder
    }

    /// A colored, filled person glyph for menu rows without a profile photo.
    /// Hue is picked deterministically from the user id so the same person keeps
    /// one color across launches (String.hashValue is per-process seeded, so we
    /// sum unicode scalars instead of hashing).
    static func coloredAvatarPlaceholder(for user: User) -> UIImage? {
        let palette: [UIColor] = [
            Constants.Colors.primary, .systemOrange, .systemPink, .systemPurple,
            .systemTeal, .systemGreen, .systemIndigo, .systemRed
        ]
        let seed = user.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let color = palette[seed % palette.count]
        return UIImage(
            systemName: "person.crop.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        )?.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    /// Aspect-fill crops an image into a small circle for use as a menu icon.
    static func circularMenuImage(_ image: UIImage, diameter: CGFloat = 26) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            let scale = max(diameter / max(image.size.width, 1), diameter / max(image.size.height, 1))
            let width = image.size.width * scale
            let height = image.size.height * scale
            image.draw(in: CGRect(x: (diameter - width) / 2, y: (diameter - height) / 2, width: width, height: height))
        }.withRenderingMode(.alwaysOriginal)
    }

    // MARK: - Category menu

    func categoryMenuElements() -> [UIMenuElement] {
        let state = self.state
        // Faceted: the options come from the set filtered by the OTHER active
        // filters (connection + region), so "Dan · Rhode Island" offers only
        // the categories Dan actually has in Rhode Island.
        var facetBase = state.facetBase
        if let regionId = state.selectedChipRegionId,
           let region = state.chipRegionGroups.first(where: { $0.id == regionId }) {
            facetBase = facetBase.filter { region.contains($0) }
        }
        var groups = PlaceCategoryGroup.present(in: facetBase.map { $0.category.rawValue })
        // Never hide the active selection, even at zero — you need the row to
        // un-pick it.
        if state.selectedChipGroup != .all && !groups.contains(state.selectedChipGroup) {
            groups.append(state.selectedChipGroup)
        }
        return groups.map { group in
            UIAction(title: group == .all ? "All Categories" : group.title,
                     image: Self.categoryMenuIcon(for: group),
                     state: state.selectedChipGroup == group ? .on : .off) { [weak self] _ in
                self?.perform(.selectChipGroup(group))
            }
        }
    }

    /// Menu icon matching the map pins' color coding: each group shows its
    /// category's glyph in its pin color, so the dropdown reads like a legend.
    private static func categoryMenuIcon(for group: PlaceCategoryGroup) -> UIImage? {
        if group == .all {
            return UIImage(systemName: "square.grid.2x2")?
                .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        }
        let raw = group.categories.contains("other")
            ? "other"
            : (group.categories.sorted().first ?? "other")
        let category = PlaceCategory(rawValue: raw) ?? .other
        return UIImage(systemName: category.systemIconName)?
            .withTintColor(category.color, renderingMode: .alwaysOriginal)
    }

    // MARK: - Place (region) menu

    /// All Places, Near me (when a fix landed), then states most-places-first.
    func placeMenuElements() -> [UIMenuElement] {
        let state = self.state
        // Faceted: regions and their counts come from the set filtered by the
        // OTHER active filters (connection + category), so "Dan · Hotels"
        // shows "Rhode Island (2)" and no Arizona row at all. Selecting a
        // region still stores the id, which applyFilter resolves against the
        // full chipRegionGroups (same ids — same grouper).
        var facetBase = state.facetBase
        if state.selectedChipGroup != .all {
            facetBase = facetBase.filter { state.selectedChipGroup.matches($0.category.rawValue) }
        }
        var facetGroups = RegionGrouper.groups(for: facetBase, origin: state.chipOrigin)
        // Never hide the active selection, even at zero — you need the row to
        // un-pick it.
        if let selectedId = state.selectedChipRegionId,
           !facetGroups.contains(where: { $0.id == selectedId }),
           let full = state.chipRegionGroups.first(where: { $0.id == selectedId }) {
            facetGroups.append(RegionGroup(
                id: full.id, title: full.title, count: 0,
                placeIds: [], centroid: full.centroid
            ))
        }

        var actions: [UIAction] = [
            UIAction(title: "All Places",
                     image: Self.emojiImage("🌎"),
                     state: state.selectedChipRegionId == nil ? .on : .off) { [weak self] _ in
                self?.perform(.selectRegion(id: nil))
            }
        ]
        for group in facetGroups {
            actions.append(UIAction(title: "\(group.title) (\(group.count))",
                                    image: Self.regionMenuImage(for: group),
                                    state: state.selectedChipRegionId == group.id ? .on : .off) { [weak self] _ in
                self?.perform(.selectRegion(id: group.id))
            })
        }
        return actions
    }

    /// Row image for a region: the bundled state flag for US states, the emoji
    /// flag for countries, a location glyph for "Near me". States without a
    /// flag asset (e.g. DC) simply show no image.
    private static func regionMenuImage(for group: RegionGroup) -> UIImage? {
        if group.id == "near-me" {
            return UIImage(systemName: "location.fill")?
                .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        }
        if group.id == "other-countries" {
            return UIImage(systemName: "globe")?
                .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        }
        if group.id.hasPrefix("state:") {
            let code = String(group.id.dropFirst("state:".count)).lowercased()
            // Every code RegionGrouper can emit has a bundled flag (50 states +
            // DC/PR/VI/GU), so states appearing for the first time — a user's
            // first Montana place — get their flag with no code change. The US
            // flag is the safety net if an asset is ever missing, so a state
            // row never shows imageless next to flagged siblings.
            if let flag = UIImage(named: "flag-us-\(code)") {
                return flag.withRenderingMode(.alwaysOriginal)
            }
            return emojiFlagImage(countryCode: "US")
        }
        if group.id.hasPrefix("country:") {
            // Rendered from the ISO2 code at runtime — any country that ever
            // appears gets its emoji flag with no bundled asset.
            let code = String(group.id.dropFirst("country:".count))
            return emojiFlagImage(countryCode: code)
        }
        return nil
    }

    /// Renders a country's emoji flag (🇨🇦) into a menu-sized image.
    static func emojiFlagImage(countryCode: String) -> UIImage? {
        let base: UInt32 = 127397
        var flag = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            guard let indicator = UnicodeScalar(base + scalar.value) else { return nil }
            flag.append(String(indicator))
        }
        return emojiImage(flag)
    }

    /// Renders any emoji (🌎, 🇨🇦) into a menu-sized image — full color, unlike
    /// tinted SF Symbols.
    static func emojiImage(_ emoji: String, fontSize: CGFloat = 20) -> UIImage? {
        let attributed = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: fontSize)])
        let size = attributed.size()
        guard size.width > 0 else { return nil }
        return UIGraphicsImageRenderer(size: size).image { _ in
            attributed.draw(at: .zero)
        }.withRenderingMode(.alwaysOriginal)
    }

    private func perform(_ action: MapFilterMenuAction) {
        delegate?.menuBuilder(self, perform: action)
    }
}
