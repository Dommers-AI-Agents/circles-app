import Testing
import UIKit
import CoreLocation
@testable import Circles_iOS

/// The add-place asset pipeline: a canonical match supplies Google details,
/// photos and description without a Google call, and a response that
/// belongs to an earlier selection never touches the form.
@MainActor
struct PlaceAssetLoaderTests {
    final class RecordingForm: PlaceAssetLoaderDelegate {
        var selectedGooglePlaceDetails: GooglePlaceDetails?
        var uploadedPhotoUrls: [String] = []
        var downloadedGoogleImage: UIImage?
        var downloadedLookAroundImage: UIImage?
        var photosWereAutoPopulated = false
        var selectedImage: UIImage?
        var clearCount = 0
        var shownPhotos: [UIImage] = []
        var descriptionUpgrades: [String?] = []

        func clearAutoPopulatedPhotoState() { clearCount += 1 }
        func showPipelinePhoto(_ image: UIImage) { shownPhotos.append(image) }
        func upgradeDescriptionWithEditorialSummary(_ summary: String?) { descriptionUpgrades.append(summary) }
    }

    private static func match(photos: [String], description: String? = "Canonical text") -> KnownPlaceMatch {
        KnownPlaceMatch(globalPlaceId: "gp1", googlePlaceId: "google-1", name: "Cafe",
                        address: "1 Main St", category: "cafe", description: description, photos: photos)
    }

    /// The loader hops to the main queue before applying a result; wait for
    /// everything queued ahead of us to run.
    private func drainMainQueue() async {
        for _ in 0..<3 {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { c.resume() }
            }
        }
    }

    @Test func nilTokenIsAlwaysCurrent() {
        let live = UUID()
        #expect(PlaceAssetLoader.isCurrent(token: nil, live: live))
        #expect(PlaceAssetLoader.isCurrent(token: live, live: live))
        #expect(!PlaceAssetLoader.isCurrent(token: UUID(), live: live))
    }

    @Test func canonicalMatchFillsDetailsPhotosAndDescription() async {
        let form = RecordingForm()
        let loader = PlaceAssetLoader()
        loader.delegate = form
        let preview = UIImage()
        loader.matchKnownPlace = { _, _, _, _, completion in
            completion(.success(Self.match(photos: ["p1", "p2", "p3", "p4", "p5", "p6", "p7"])))
        }
        loader.loadImage = { url, completion in
            #expect(url == "p1")
            completion(preview)
        }

        loader.fetchPlaceAssets(name: "Cafe", coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2), address: nil)
        await drainMainQueue()

        #expect(form.clearCount == 1)
        #expect(form.selectedGooglePlaceDetails?.placeID == "google-1")
        #expect(form.selectedGooglePlaceDetails?.address == "1 Main St")
        #expect(form.uploadedPhotoUrls == ["p1", "p2", "p3", "p4", "p5"])
        #expect(form.photosWereAutoPopulated)
        #expect(form.selectedImage === preview)
        #expect(form.shownPhotos.count == 1)
        #expect(form.descriptionUpgrades == ["Canonical text"])
    }

    @Test func userPhotosAreNeverReplacedByCanonicalOnes() async {
        let form = RecordingForm()
        form.uploadedPhotoUrls = ["mine"]
        let loader = PlaceAssetLoader()
        loader.delegate = form
        loader.matchKnownPlace = { _, _, _, _, completion in completion(.success(Self.match(photos: ["p1"]))) }
        loader.loadImage = { _, _ in Issue.record("must not load a preview when the user already has photos") }

        loader.fetchPlaceAssets(name: "Cafe", coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2), address: nil)
        await drainMainQueue()

        #expect(form.uploadedPhotoUrls == ["mine"])
        #expect(!form.photosWereAutoPopulated)
        #expect(form.selectedGooglePlaceDetails?.placeID == "google-1")
    }

    @Test func aResponseForAnEarlierSelectionIsIgnored() async {
        let form = RecordingForm()
        let loader = PlaceAssetLoader()
        loader.delegate = form
        var pending: [(Result<KnownPlaceMatch?, Error>) -> Void] = []
        loader.matchKnownPlace = { _, _, _, _, completion in pending.append(completion) }
        loader.loadImage = { _, completion in completion(UIImage()) }

        loader.fetchPlaceAssets(name: "First", coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2), address: nil)
        let firstToken = loader.requestToken
        loader.fetchPlaceAssets(name: "Second", coordinate: CLLocationCoordinate2D(latitude: 3, longitude: 4), address: nil)
        #expect(loader.requestToken != firstToken)
        #expect(form.clearCount == 2)

        // The stale response lands first
        pending[0](.success(KnownPlaceMatch(globalPlaceId: "stale", googlePlaceId: "stale-google", name: "First",
                                            address: nil, category: nil, description: "stale", photos: ["stale.jpg"])))
        await drainMainQueue()
        #expect(form.selectedGooglePlaceDetails == nil)
        #expect(form.uploadedPhotoUrls.isEmpty)
        #expect(form.descriptionUpgrades.isEmpty)

        pending[1](.success(Self.match(photos: ["p1"])))
        await drainMainQueue()
        #expect(form.selectedGooglePlaceDetails?.placeID == "google-1")
        #expect(form.uploadedPhotoUrls == ["p1"])
    }
}
