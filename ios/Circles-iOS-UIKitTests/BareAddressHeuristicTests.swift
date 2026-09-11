import Testing
@testable import Circles_iOS

/// Street-address results vs. businesses, and which nearby business names
/// are close enough to an address to suggest.
struct BareAddressHeuristicTests {
    @Test func addressLineNamesAreBare() {
        #expect(BareAddressHeuristic.isBareAddress(name: "300 East Blvd", hasPointOfInterestCategory: false,
                                                   subThoroughfare: "300", thoroughfare: "East Blvd"))
        #expect(BareAddressHeuristic.isBareAddress(name: "East Blvd", hasPointOfInterestCategory: false,
                                                   subThoroughfare: "300", thoroughfare: "East Blvd"))
        // Punctuation and case don't matter
        #expect(BareAddressHeuristic.isBareAddress(name: "121 W. Trade St", hasPointOfInterestCategory: false,
                                                   subThoroughfare: "121", thoroughfare: "W Trade St"))
    }

    @Test func businessesAreNotBare() {
        #expect(!BareAddressHeuristic.isBareAddress(name: "Amelie's", hasPointOfInterestCategory: false,
                                                    subThoroughfare: "300", thoroughfare: "East Blvd"))
        // A POI category means a business even when the name is the address
        #expect(!BareAddressHeuristic.isBareAddress(name: "300 East Blvd", hasPointOfInterestCategory: true,
                                                    subThoroughfare: "300", thoroughfare: "East Blvd"))
        #expect(!BareAddressHeuristic.isBareAddress(name: nil, hasPointOfInterestCategory: false,
                                                    subThoroughfare: "300", thoroughfare: "East Blvd"))
        #expect(!BareAddressHeuristic.isBareAddress(name: "...", hasPointOfInterestCategory: false,
                                                    subThoroughfare: "300", thoroughfare: "East Blvd"))
    }

    @Test func relatedNamesContainEachOther() {
        #expect(BareAddressHeuristic.namesRelated(business: "300 East", address: "300 East Blvd"))
        #expect(BareAddressHeuristic.namesRelated(business: "300 East Blvd Cafe", address: "300 East Blvd"))
        #expect(BareAddressHeuristic.namesRelated(business: "Café 300 EAST", address: "300 east blvd"))
    }

    @Test func abbreviationDriftStillRelates() {
        // Two shared tokens and at most one business token unmatched
        #expect(BareAddressHeuristic.namesRelated(business: "121 W Trade", address: "121 West Trade St"))
        #expect(!BareAddressHeuristic.namesRelated(business: "Bojangles", address: "300 East Blvd"))
        #expect(!BareAddressHeuristic.namesRelated(business: "", address: "300 East Blvd"))
    }
}
