import Testing
import UIKit
@testable import Circles_iOS

/// Tapping the place page's top carousel opens the full-screen viewer on the
/// same photo, with every other photo a swipe away.
struct CarouselPhotoViewerMapTests {
    private func attributed(_ url: String) -> AttributedPhoto {
        AttributedPhoto(photoId: url, url: url, uploadedBy: "u1", uploadedByName: "Wes",
                        uploadedAt: Date(), source: .userUpload, width: nil, height: nil,
                        fileSize: nil, likes: nil, likesCount: nil)
    }

    @Test func tappedPhotoOpensAtItsPlaceAmongPhotos() {
        let items: [MediaItem] = [
            .attributedPhoto(photo: attributed("cover")),
            .photo(url: "legacy"),
            .attributedPhoto(photo: attributed("third"))
        ]
        #expect(CarouselPhotoViewerMap.viewer(for: items, tappedAt: 2)
                == .init(urls: ["cover", "legacy", "third"], startIndex: 2))
    }

    @Test func videosAndUnuploadedPhotosAreSkipped() {
        let items: [MediaItem] = [
            .photoImage(image: UIImage()),
            .attributedPhoto(photo: attributed("a")),
            .video(thumbnailUrl: "t", videoUrl: "v"),
            .photo(url: "b")
        ]
        // Carousel index 3 is the second photo with a URL
        #expect(CarouselPhotoViewerMap.viewer(for: items, tappedAt: 3)
                == .init(urls: ["a", "b"], startIndex: 1))
    }

    @Test func tappingSomethingWithoutAPhotoOpensNothing() {
        let items: [MediaItem] = [.video(thumbnailUrl: nil, videoUrl: "v"), .photoImage(image: UIImage()), .photo(url: nil), .photo(url: "")]
        for index in 0..<items.count {
            #expect(CarouselPhotoViewerMap.viewer(for: items, tappedAt: index) == nil)
        }
        #expect(CarouselPhotoViewerMap.viewer(for: items, tappedAt: 9) == nil)
    }
}
