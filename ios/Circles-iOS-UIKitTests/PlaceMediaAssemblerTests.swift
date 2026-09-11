import Testing
import UIKit
@testable import Circles_iOS

/// The carousel merge rules: attributed venue photos first (cover leading),
/// legacy URLs once each, local captures reused instead of re-fetched, videos
/// after photos, and a single placeholder when there's nothing.
struct PlaceMediaAssemblerTests {
    private func attributed(_ url: String) -> AttributedPhoto {
        AttributedPhoto(photoId: url, url: url, uploadedBy: "u1", uploadedByName: "Wes",
                        uploadedAt: Date(), source: .userUpload, width: nil, height: nil,
                        fileSize: nil, likes: nil, likesCount: nil)
    }
    private let imageA = UIImage()
    private let imageB = UIImage()

    /// Compact fingerprint of an item list so expectations read as one line.
    private func describe(_ items: [MediaItem]) -> [String] {
        items.map { item in
            switch item {
            case .attributedPhoto(let p): return "attr:\(p.url)"
            case .photo(let url): return "url:\(url ?? "nil")"
            case .photoImage(let image): return image === imageA ? "img:A" : (image === imageB ? "img:B" : "img:?")
            case .video(_, let videoUrl): return "video:\(videoUrl ?? "nil")"
            }
        }
    }

    @Test func nothingYieldsOnePlaceholder() {
        #expect(describe(PlaceMediaAssembler().assemble()) == ["url:nil"])
    }

    @Test func coverPhotoLeadsTheAttributedPhotos() {
        var a = PlaceMediaAssembler()
        a.attributedPhotos = [attributed("p1"), attributed("p2"), attributed("cover")]
        a.coverPhotoUrl = "cover"
        #expect(describe(a.assemble()) == ["attr:cover", "attr:p1", "attr:p2"])
    }

    @Test func unknownCoverUrlChangesNothing() {
        var a = PlaceMediaAssembler()
        a.attributedPhotos = [attributed("p1"), attributed("p2")]
        a.coverPhotoUrl = "missing"
        #expect(describe(a.assemble()) == ["attr:p1", "attr:p2"])
    }

    @Test func legacyPhotosFollowAndNeverDuplicateAnAttributedUrl() {
        var a = PlaceMediaAssembler()
        a.attributedPhotos = [attributed("shared")]
        a.legacyPhotoUrls = ["shared", "legacyOnly", "legacyOnly"]
        #expect(describe(a.assemble()) == ["attr:shared", "url:legacyOnly"])
    }

    @Test func legacyUrlAlreadyHeldLocallyUsesTheImage() {
        var a = PlaceMediaAssembler()
        a.legacyPhotoUrls = ["known", "remote"]
        a.localPhotos = [.init(image: imageA, url: "known")]
        #expect(describe(a.assemble()) == ["img:A", "url:remote"])
    }

    @Test func localPhotosNotOnTheServerYetAreAppendedOnce() {
        var a = PlaceMediaAssembler()
        a.attributedPhotos = [attributed("p1")]
        a.localPhotos = [
            .init(image: imageA, url: "p1"),          // already shown as attributed → skipped
            .init(image: imageB, url: "pendingUpload"),
            .init(image: imageA, url: nil)            // no URL yet → always shown
        ]
        #expect(describe(a.assemble()) == ["attr:p1", "img:B", "img:A"])
    }

    @Test func videosComeAfterPhotosAndSuppressThePlaceholder() {
        var a = PlaceMediaAssembler()
        a.legacyPhotoUrls = ["p1"]
        a.videoUrls = ["v1", "v2"]
        #expect(describe(a.assemble()) == ["url:p1", "video:v1", "video:v2"])

        var onlyVideo = PlaceMediaAssembler()
        onlyVideo.videoUrls = ["v1"]
        #expect(describe(onlyVideo.assemble()) == ["video:v1"])
    }
}
