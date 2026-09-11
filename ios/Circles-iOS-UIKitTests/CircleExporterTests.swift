import Testing
import Foundation
@testable import Circles_iOS

/// Byte-for-byte fixtures for the circle export formats.
struct CircleExporterTests {
    private func place(_ name: String, address: String = "", phone: String? = nil, website: String? = nil,
                       notes: String? = nil, category: PlaceCategory = .restaurant) -> Place {
        Place(id: name, name: name, description: nil, address: address, location: nil, website: website, phone: phone,
              googlePlaceId: nil, photos: nil, videos: nil, category: category, customCategoryId: nil,
              subcategory: nil, rating: nil, userRatingsTotal: nil, notes: notes, privateNotes: nil,
              publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
              likesCount: nil, commentsCount: nil, circleId: nil, addedBy: "u", addedByUser: nil,
              privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    @Test func csvSwapsCommasForSemicolonsAndFlattensNotes() {
        let places = [
            place("Joe's, Diner", address: "1 Main St, Town", phone: "555,1234", website: "https://x.test",
                  notes: "Great\nfries, really", category: .restaurant),
            place("Park", category: .other)
        ]
        let expected = "Name,Category,Address,Phone,Website,Notes\n"
            + "Joe's; Diner,restaurant,1 Main St; Town,555;1234,https://x.test,Great fries; really\n"
            + "Park,other,,,,\n"
        #expect(CircleExporter.csv(places: places) == expected)
    }

    @Test func textListsOnlyPresentFields() {
        let places = [
            place("Cafe", address: "2 Side St", phone: "555", website: nil, notes: ""),
            place("Bar", website: "https://bar.test", notes: "Late")
        ]
        let expected = "Weekend\n=======\n\n"
            + "1. Cafe\n   Address: 2 Side St\n   Phone: 555\n\n"
            + "2. Bar\n   Website: https://bar.test\n   Notes: Late\n\n"
        #expect(CircleExporter.text(circleName: "Weekend", places: places) == expected)
    }

    @Test func pdfIsAPdfDocumentEvenWhenEmpty() {
        let data = CircleExporter.pdf(circleName: "Empty", places: [])
        #expect(data.count > 0)
        #expect(String(data: data.prefix(4), encoding: .ascii) == "%PDF")
    }
}
