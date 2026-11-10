import Testing
import Foundation
import UIKit
@testable import Circles_iOS

/// The Instagram card for a store's new post: wording, and a render at
/// Instagram's exact sizes (the PNGs land in the session scratchpad when it
/// exists, for a look).
struct StorePostCardTests {

    private typealias C = StorePostCopy

    @Test func headlineAndDetailPerPostKind() {
        let offer = StorePost.offer(title: "Free coffee", pointsCost: 100)
        #expect(C.headline(offer) == "Free coffee")
        #expect(C.detail(offer, storeName: "Sal's") == "100 points at Sal's in FavCircles")

        let note = StorePost.announcement(title: "New fall menu", message: "Pumpkin everything, starting Monday.", eventStart: nil)
        #expect(C.headline(note) == "New fall menu")
        #expect(C.detail(note, storeName: "Sal's") == "Pumpkin everything, starting Monday.")
        #expect(C.sheetTitle(note) == "Announcement posted")

        var parts = DateComponents(); parts.year = 2026; parts.month = 11; parts.day = 13; parts.hour = 19
        let friday = Calendar.current.date(from: parts)!
        let event = StorePost.announcement(title: "Live music", message: "", eventStart: friday)
        #expect(C.detail(event, storeName: "Sal's") == "Friday, Nov 13 · 7:00 PM")
        #expect(C.sheetTitle(event) == "Event posted")
        #expect(C.sheetMessage(alertedLine: nil) == "It's on your place page and in the Locals tab. Share it on Instagram too?")
        #expect(C.sheetMessage(alertedLine: "Posted, and sent as an alert to 12 followers who turned on alerts.").hasSuffix("Share it on Instagram too?"))
    }

    @Test func neverPromisesTexting() {
        let offer = StorePost.offer(title: "Free coffee", pointsCost: 100)
        #expect(C.footer(offer) == "Earn it with FavCircles · favcircles.com")
        #expect(C.footer(.announcement(title: "x", message: "", eventStart: nil)) == "Follow us on FavCircles · favcircles.com")
        for text in [C.footer(offer), C.footer(.announcement(title: "x", message: "", eventStart: nil)), C.sheetMessage(alertedLine: nil), C.instagramMissing, C.shareStory, C.sharePost] {
            #expect(!text.lowercased().contains("text"), "\(text)")
            #expect(!text.lowercased().contains("sms"), "\(text)")
        }
    }

    @Test func rendersAtInstagramSizes() {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { ctx in
            UIColor(red: 0.55, green: 0.35, blue: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            UIColor(red: 0.9, green: 0.8, blue: 0.6, alpha: 1).setFill()
            ctx.fill(CGRect(x: 100, y: 120, width: 600, height: 300))
        }
        for format in StorePostCard.Format.allCases {
            let image = StorePostCard.render(format, photo: photo, storeName: "Sal's Coffee",
                                             headline: "Free coffee with any pastry",
                                             detail: "100 points at Sal's Coffee in FavCircles",
                                             footer: "Earn it with FavCircles · favcircles.com")
            #expect(image.size == format.size)
            #expect(image.scale == 1)
            let noPhoto = StorePostCard.render(format, photo: nil, storeName: "Sal's Coffee", headline: "Live music Friday", detail: "Friday, Nov 13 · 7:00 PM",
                                               footer: "Follow us on FavCircles · favcircles.com")
            #expect(noPhoto.size == format.size)

            let dir = "/private/tmp/claude-501/-Users-wesleysgroi-circles-app/bdad15da-518e-4acb-9d92-cecf54bfee5a/scratchpad"
            if FileManager.default.fileExists(atPath: dir), let png = image.pngData() {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/store-post-\(format).png"))
                try? noPhoto.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/store-post-\(format)-nophoto.png"))
            }
        }
    }
}
