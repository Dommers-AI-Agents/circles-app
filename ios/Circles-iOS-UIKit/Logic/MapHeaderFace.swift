import Foundation

/// Whose face the map's Connection dropdown wears (Wes, 2026-11-19: "The large
/// map view from home page should also show a small avatar of the person
/// filtered"). Same rule as the home page's avatar chip: a filtered person
/// shows their photo, My Places shows yours, Everyone / My Connections show
/// nobody in particular.
enum MapHeaderFace {
    static func user(selectedId: String?, selectedUser: User?, me: User?) -> User? {
        switch selectedId {
        case nil, HomePlaceFilter.myConnectionsOnlyId: return nil
        case HomePlaceFilter.myPlacesOnlyId: return me
        default: return selectedUser
        }
    }
}
