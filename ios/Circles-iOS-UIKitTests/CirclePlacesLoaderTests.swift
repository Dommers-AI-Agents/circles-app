import Testing
import Foundation
@testable import Circles_iOS

/// The circle screen's places fetch: endpoint choice and the order of the
/// UI callbacks on success and failure.
struct CirclePlacesLoaderTests {
    final class Recorder: CirclePlacesLoaderDelegate {
        var events: [String] = []
        func loaderDidLoadPlaces(_ places: [Place]) { events.append("loaded:\(places.count)") }
        func loaderDidFailToLoadPlaces(_ error: Error) { events.append("failed") }
        func loaderDidFinishLoadingPlaces() { events.append("finished") }
    }

    private struct Boom: Error {}

    private func circle(privacy: PrivacyLevel) -> Circle {
        Circle(id: "c1", name: "Weekend", description: nil, coverImage: nil, owner: "u", ownerDetails: nil,
               editors: nil, editorsDetails: nil, places: nil, placesCount: nil, placesWithDetails: nil,
               privacy: privacy, allowNetworkEdit: nil, showOnMap: nil, category: .other,
               location: nil, tags: nil, sharedWith: nil, followers: nil, activeShares: nil,
               shareSettings: nil, isSharedWithMe: nil, sharedBy: nil, myAccessLevel: nil,
               createdAt: Date(), updatedAt: Date())
    }

    private func place(_ id: String) -> Place {
        Place(id: id, name: id, description: nil, address: "", location: nil, website: nil, phone: nil,
              googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant, customCategoryId: nil,
              subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
              publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
              likesCount: nil, commentsCount: nil, circleId: "c1", addedBy: "u", addedByUser: nil,
              privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { c.resume() }
        }
    }

    @Test func onlyPublicCirclesOpenedFromALinkUseThePublicEndpoint() {
        #expect(CirclePlacesLoader.usesPublicEndpoint(privacy: .public, isSharedViaLink: true))
        #expect(!CirclePlacesLoader.usesPublicEndpoint(privacy: .public, isSharedViaLink: false))
        #expect(!CirclePlacesLoader.usesPublicEndpoint(privacy: .private, isSharedViaLink: true))
        #expect(!CirclePlacesLoader.usesPublicEndpoint(privacy: .myNetwork, isSharedViaLink: true))
    }

    @Test func successReportsPlacesThenFinishes() async {
        let recorder = Recorder()
        let loader = CirclePlacesLoader()
        loader.delegate = recorder
        var calledEndpoint = ""
        loader.fetchPublic = { _, completion in calledEndpoint = "public"; completion(.success([self.place("a"), self.place("b")])) }
        loader.fetchAuthenticated = { _, completion in calledEndpoint = "auth"; completion(.success([self.place("a")])) }

        loader.fetchPlaces(for: circle(privacy: .public), isSharedViaLink: true)
        await drainMainQueue()
        #expect(calledEndpoint == "public")
        #expect(recorder.events == ["loaded:2", "finished"])

        recorder.events = []
        loader.fetchPlaces(for: circle(privacy: .public), isSharedViaLink: false)
        await drainMainQueue()
        #expect(calledEndpoint == "auth")
        #expect(recorder.events == ["loaded:1", "finished"])
    }

    @Test func failureReportsThenFinishes() async {
        let recorder = Recorder()
        let loader = CirclePlacesLoader()
        loader.delegate = recorder
        loader.fetchAuthenticated = { _, completion in completion(.failure(Boom())) }

        loader.fetchPlaces(for: circle(privacy: .private), isSharedViaLink: false)
        await drainMainQueue()
        #expect(recorder.events == ["failed", "finished"])
    }
}
