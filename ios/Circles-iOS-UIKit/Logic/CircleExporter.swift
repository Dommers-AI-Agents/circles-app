import UIKit

/// Builds the circle export documents (PDF, CSV, plain text) from a circle
/// name and its places. Output is identical to what the circle screen used
/// to build inline; the CSV/text builders are pure strings, the PDF uses
/// UIGraphicsPDFRenderer (the one UIKit dependency in this file).
enum CircleExporter {
    /// Comma-separated table; commas in values become semicolons and
    /// newlines in notes become spaces (no quoting — legacy format).
    static func csv(places: [Place]) -> String {
        var csvText = "Name,Category,Address,Phone,Website,Notes\n"

        for place in places {
            let name = place.name.replacingOccurrences(of: ",", with: ";")
            let category = place.category.rawValue
            let address = place.address.replacingOccurrences(of: ",", with: ";")
            let phone = (place.phone ?? "").replacingOccurrences(of: ",", with: ";")
            let website = (place.website ?? "").replacingOccurrences(of: ",", with: ";")
            let notes = (place.notes ?? "").replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")

            csvText += "\(name),\(category),\(address),\(phone),\(website),\(notes)\n"
        }
        return csvText
    }

    /// Numbered list under an underlined title.
    static func text(circleName: String, places: [Place]) -> String {
        var textContent = "\(circleName)\n"
        textContent += String(repeating: "=", count: circleName.count) + "\n\n"

        for (index, place) in places.enumerated() {
            textContent += "\(index + 1). \(place.name)\n"
            if !place.address.isEmpty {
                textContent += "   Address: \(place.address)\n"
            }
            if let phone = place.phone {
                textContent += "   Phone: \(phone)\n"
            }
            if let website = place.website {
                textContent += "   Website: \(website)\n"
            }
            if let notes = place.notes, !notes.isEmpty {
                textContent += "   Notes: \(notes)\n"
            }
            textContent += "\n"
        }
        return textContent
    }

    /// US-letter PDF: title, then one numbered line per place with the
    /// address underneath; a new page starts near the bottom margin.
    static func pdf(circleName: String, places: [Place]) -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "Circles App",
            kCGPDFContextTitle: circleName
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageWidth = 8.5 * 72.0
        let pageHeight = 11 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { (context) in
            context.beginPage()

            // Title
            let titleAttributes = [
                NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 24)
            ]
            circleName.draw(at: CGPoint(x: 20, y: 20), withAttributes: titleAttributes)

            // Places
            var yPosition: CGFloat = 80
            let placeAttributes = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: 14)
            ]

            for (index, place) in places.enumerated() {
                let placeText = "\(index + 1). \(place.name)"
                placeText.draw(at: CGPoint(x: 20, y: yPosition), withAttributes: placeAttributes)

                if !place.address.isEmpty {
                    let addressText = "   \(place.address)"
                    let addressAttributes = [
                        NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12),
                        NSAttributedString.Key.foregroundColor: UIColor.gray
                    ]
                    addressText.draw(at: CGPoint(x: 20, y: yPosition + 20), withAttributes: addressAttributes)
                    yPosition += 40
                } else {
                    yPosition += 25
                }

                // Start new page if needed
                if yPosition > pageHeight - 100 {
                    context.beginPage()
                    yPosition = 20
                }
            }
        }
    }
}
