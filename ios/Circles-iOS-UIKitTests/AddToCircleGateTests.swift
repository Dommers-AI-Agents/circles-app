import Testing
import Foundation
@testable import Circles_iOS

/// When the place page offers "Add to Circle", and what counts as the
/// same venue as one the user already saved.
struct AddToCircleGateTests {
    private func place(_ id: String, name: String = "Amelie's", address: String = "2424 N Davidson St",
                       googlePlaceId: String? = nil, globalPlaceId: String? = nil, addedBy: String = "bob") -> Place {
        Place(id: id, globalPlaceId: globalPlaceId, name: name, description: nil, address: address, location: nil,
              website: nil, phone: nil, googlePlaceId: googlePlaceId, photos: nil, videos: nil, category: .cafe,
              customCategoryId: nil, subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
              publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
              likesCount: nil, commentsCount: nil, circleId: nil, addedBy: addedBy, addedByUser: nil,
              privacy: .public, createdAt: Date(), updatedAt: Date())
    }
    private func circle(_ id: String, places: [String]?) -> Circle {
        Circle(id: id, name: id, description: nil, coverImage: nil, owner: "me", ownerDetails: nil,
               editors: nil, editorsDetails: nil, places: places, placesCount: nil, placesWithDetails: nil,
               privacy: .public, allowNetworkEdit: nil, showOnMap: nil, category: .other,
               location: nil, tags: nil, sharedWith: nil, followers: nil, activeShares: nil,
               shareSettings: nil, isSharedWithMe: nil, sharedBy: nil, myAccessLevel: nil,
               createdAt: Date(), updatedAt: Date())
    }

    @Test func ownSaveIsHidden() {
        #expect(AddToCircleGate.isOwnSave(place("p", addedBy: "me"), currentUserId: "me"))
        #expect(!AddToCircleGate.isOwnSave(place("p", addedBy: "bob"), currentUserId: "me"))
    }

    @Test func circlesDecideBeforeTheVenueCheck() {
        let target = place("doc-1")
        #expect(AddToCircleGate.verdict(for: target, in: []) == .hide)
        #expect(AddToCircleGate.verdict(for: target, in: [circle("c1", places: ["doc-1"])]) == .hide)
        #expect(AddToCircleGate.verdict(for: target, in: [circle("c1", places: ["other"]), circle("c2", places: nil)])
                == .checkVenueMatch(circleIds: ["c1", "c2"]))
    }

    @Test func venueCheckHidesOnlyForTheSameVenue() {
        let target = place("doc-1", googlePlaceId: "g1")
        #expect(AddToCircleGate.verdictAfterVenueCheck(for: target, myPlaces: [place("mine", name: "Elsewhere", googlePlaceId: "g2")]) == .show)
        #expect(AddToCircleGate.verdictAfterVenueCheck(for: target, myPlaces: [place("mine", name: "Elsewhere", googlePlaceId: "g1")]) == .hide)
        #expect(AddToCircleGate.verdictAfterVenueCheck(for: target, myPlaces: []) == .show)
    }

    @Test func sameVenueByIds() {
        let byGoogle = place("a", googlePlaceId: "g1")
        #expect(AddToCircleGate.isSameVenue(byGoogle, as: place("b", name: "Other", address: "x", googlePlaceId: "g1")))
        #expect(!AddToCircleGate.isSameVenue(place("a", googlePlaceId: ""), as: place("b", name: "Other", address: "x", googlePlaceId: "")))

        let byGlobal = place("a", globalPlaceId: "G")
        #expect(AddToCircleGate.isSameVenue(byGlobal, as: place("b", name: "Other", address: "x", globalPlaceId: "G")))
        #expect(AddToCircleGate.isSameVenue(byGlobal, as: place("G", name: "Other", address: "x")))

        // The screen may hold a converted GlobalPlace whose id IS the global id
        #expect(AddToCircleGate.isSameVenue(place("G", name: "Other", address: "x"), as: place("b", name: "Diff", address: "y", globalPlaceId: "G")))
    }

    @Test func sameVenueByNameAndAddressNeedsAnAddress() {
        let target = place("a", name: " Amelie's ", address: "2424 N Davidson St")
        #expect(AddToCircleGate.isSameVenue(target, as: place("b", name: "amelie's", address: "2424 n davidson st ")))
        #expect(!AddToCircleGate.isSameVenue(target, as: place("b", name: "amelie's", address: "elsewhere")))
        #expect(!AddToCircleGate.isSameVenue(place("a", address: ""), as: place("b", address: "")))
    }
}
