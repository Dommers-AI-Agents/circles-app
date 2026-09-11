import Foundation

/// The full-screen map's people scope: which places survive the connection
/// dropdown (Everyone / My Connections / My Places / one person).
///
/// This is deliberately NOT `HomePlaceFilter`. The home map attributes a
/// place to its circle's owner and drops hidden circles; the modal map works
/// from lists the server already bucketed per connection (which carry
/// circle-owner semantics) and adds an `addedBy` sweep over the current
/// places so viewport-fetched places that were never bucketed still show.
/// A place saved under a connection's legacy account id is kept either way.
enum MapPlaceScope {
    struct Context {
        var currentUserId: String = ""
        /// nil = Everyone; `HomePlaceFilter.myPlacesOnlyId`,
        /// `HomePlaceFilter.myConnectionsOnlyId`, or one user's id.
        var selectedConnectionId: String?
        /// The other side of each accepted connection, in row order.
        var acceptedConnectionUserIds: [String] = []
        var followingUserIds: [String] = []
        /// Places pre-bucketed by connection user id.
        var bucketedPlaces: [String: [Place]] = [:]
    }

    static func apply(_ places: [Place], context: Context) -> [Place] {
        guard let connectionId = context.selectedConnectionId else {
            // "Everyone" — yourself + accepted connections + everyone you follow
            var authorIds = Set(context.acceptedConnectionUserIds)
            authorIds.formUnion(context.followingUserIds)
            authorIds.insert(context.currentUserId)
            authorIds = authorIds.filter { !$0.isEmpty }
            return union(bucketsFor: Array(authorIds), sweeping: places, context: context)
        }

        if connectionId == HomePlaceFilter.myPlacesOnlyId {
            return places.filter { IDNormalizer.isSameUser($0.addedBy, context.currentUserId) }
        }
        if connectionId == HomePlaceFilter.myConnectionsOnlyId {
            // Accepted connections only: the narrower cut of the default view
            return union(bucketsFor: context.acceptedConnectionUserIds, sweeping: places, context: context)
        }
        // One person: their bucket plus an addedBy match over the current
        // places. Never fall through to showing everyone's places.
        return union(bucketsFor: [connectionId], sweeping: places, context: context)
    }

    /// The named users' buckets, then any current place they added that no
    /// bucket already carried.
    private static func union(bucketsFor authorIds: [String], sweeping places: [Place], context: Context) -> [Place] {
        var scoped = authorIds.flatMap { context.bucketedPlaces[$0] ?? [] }
        let scopedIds = Set(scoped.map { $0.id })
        scoped += places.filter { place in
            !scopedIds.contains(place.id) &&
            authorIds.contains { IDNormalizer.isSameUser(place.addedBy, $0) }
        }
        return scoped
    }
}
