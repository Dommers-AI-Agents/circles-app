import UIKit
import Vision

/// Reads a receipt photo on the phone (Apple's text recognition: free, no
/// upload to read it). Lines come back top to bottom; completion on main.
enum ReceiptTextRecognizer {
    static func lines(in image: UIImage, completion: @escaping ([String]) -> Void) {
        guard let cgImage = image.cgImage else { return completion([]) }
        let request = VNRecognizeTextRequest { request, _ in
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            // Vision's origin is bottom-left: higher y is nearer the top
            let lines = observations
                .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                .compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async { completion(lines) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        DispatchQueue.global(qos: .userInitiated).async {
            do { try handler.perform([request]) } catch { DispatchQueue.main.async { completion([]) } }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
