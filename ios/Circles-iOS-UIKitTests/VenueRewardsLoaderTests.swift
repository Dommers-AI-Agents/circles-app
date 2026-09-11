import Testing
import Foundation
@testable import Circles_iOS

/// The place page's venue-side fetches: what reaches the page, and the
/// one-retry rule for transient GlobalPlace failures.
@MainActor
struct VenueRewardsLoaderTests {
    private final class RecordingDelegate: VenueRewardsLoaderDelegate {
        var place: Place
        var events: [String] = []
        var onEvent: ((String) -> Void)?
        init(place: Place) { self.place = place }

        private func record(_ event: String) { events.append(event); onEvent?(event) }
        func currentPlace(for loader: VenueRewardsLoader) -> Place { place }
        func loader(_ loader: VenueRewardsLoader, didLoadPartnerActionGroups groups: [PartnerActionGroup]) { record("partner:\(groups.count)") }
        func loader(_ loader: VenueRewardsLoader, didLoadVenueData data: PlaceVenueData) { record("venue") }
        func loaderVenueLookupFailed(_ loader: VenueRewardsLoader) { record("venueFailed") }
        func loader(_ loader: VenueRewardsLoader, didLoadGlobalPlace globalPlace: GlobalPlace) { record("global") }
        func loaderGlobalPlaceLookupFailed(_ loader: VenueRewardsLoader) { record("globalFailed") }
    }

    private func place(globalPlaceId: String? = nil) -> Place {
        Place(id: "doc-1", globalPlaceId: globalPlaceId, name: "Amelie's", description: nil, address: "", location: nil,
              website: nil, phone: nil, googlePlaceId: "g1", photos: nil, videos: nil, category: .cafe,
              customCategoryId: nil, subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
              publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
              likesCount: nil, commentsCount: nil, circleId: nil, addedBy: "bob", addedByUser: nil,
              privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    /// Runs `start`, then waits until the delegate has recorded `event`.
    private func wait(for event: String, on delegate: RecordingDelegate, start: () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            delegate.onEvent = { recorded in
                if recorded == event, !resumed { resumed = true; continuation.resume() }
            }
            start()
        }
    }

    @Test func retryOnlyForTransientErrors() {
        #expect(VenueRewardsLoader.shouldRetryGlobalPlace(after: APIError.noInternet))
        #expect(VenueRewardsLoader.shouldRetryGlobalPlace(after: APIError.requestFailed(NSError(domain: "t", code: 1))))
        #expect(!VenueRewardsLoader.shouldRetryGlobalPlace(after: NSError(domain: "t", code: 404)))
    }

    @Test func partnerActionsAreJudgedAgainstTheCurrentPlace() async {
        let delegate = RecordingDelegate(place: place())
        let loader = VenueRewardsLoader()
        loader.delegate = delegate
        loader.fetchCatalog = { completion in completion(PartnerActionCatalog(updatedAt: nil, groups: [])) }
        await wait(for: "partner:0", on: delegate) { loader.loadPartnerActions() }
        #expect(delegate.events == ["partner:0"])
    }

    @Test func venueLookupAsksByGlobalIdFirstAndReportsFailure() async {
        let delegate = RecordingDelegate(place: place(globalPlaceId: "G"))
        let loader = VenueRewardsLoader()
        loader.delegate = delegate
        var requested: (String, String?)?
        loader.fetchVenue = { placeId, googlePlaceId, completion in
            requested = (placeId, googlePlaceId)
            completion(.failure(NSError(domain: "t", code: 500)))
        }
        await wait(for: "venueFailed", on: delegate) { loader.loadVenueRewards() }
        #expect(requested?.0 == "G")
        #expect(requested?.1 == "g1")
        #expect(delegate.events == ["venueFailed"])
    }

    @Test func transientGlobalPlaceFailureRetriesOnceThenGivesUp() async {
        let delegate = RecordingDelegate(place: place())
        let loader = VenueRewardsLoader()
        loader.delegate = delegate
        loader.retryDelay = 0.01
        var calls = 0
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loader.fetchGlobalPlace = { id, completion in
                calls += 1
                #expect(id == "doc-1")
                completion(.failure(APIError.noInternet))
                if calls == 2 { continuation.resume() }
            }
            loader.loadGlobalPlaceData()
        }
        // The page hears about the first failure only; the retry fails quietly
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(calls == 2)
        #expect(delegate.events == ["globalFailed"])
    }

    @Test func finalGlobalPlaceFailureDoesNotRetry() async {
        let delegate = RecordingDelegate(place: place())
        let loader = VenueRewardsLoader()
        loader.delegate = delegate
        loader.retryDelay = 0.01
        var calls = 0
        loader.fetchGlobalPlace = { _, completion in
            calls += 1
            completion(.failure(NSError(domain: "t", code: 404)))
        }
        await wait(for: "globalFailed", on: delegate) { loader.loadGlobalPlaceData() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(calls == 1)
    }
}
