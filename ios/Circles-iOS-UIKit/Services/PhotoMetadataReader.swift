import UIKit
import ImageIO
import PhotosUI
import UniformTypeIdentifiers
import CoreLocation

/// Where and when a picked photo was taken, from the file's own GPS and EXIF
/// (the picker keeps them unless "Location Is Included" is switched off).
/// Loading a bare UIImage, as the other pickers do, throws them away.
enum PhotoMetadataReader {
    struct Picked {
        let image: UIImage                         // downscaled for display + upload; carries no metadata
        let coordinate: CLLocationCoordinate2D?
        let takenAt: Date?
    }

    /// Picker set up to hand over the original files (with their metadata).
    static func pickerConfiguration(limit: Int = 30) -> PHPickerConfiguration {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = limit
        config.preferredAssetRepresentationMode = .current
        return config
    }

    /// Reads every result, keeping the picked order. Completion on main,
    /// exactly once: after every photo, or after `timeout` with the ones read
    /// by then (an iCloud original that never downloads mustn't hang it).
    static func load(_ results: [PHPickerResult], timeout: TimeInterval = 30,
                     completion: @escaping ([Picked]) -> Void) {
        var picked = [Picked?](repeating: nil, count: results.count)
        let lock = NSLock()   // providers call back on their own queues
        var finished = false
        let finish = {
            lock.lock()
            let first = !finished
            finished = true
            let done = picked.compactMap { $0 }
            lock.unlock()
            if first { DispatchQueue.main.async { completion(done) } }
        }
        let group = DispatchGroup()
        for (index, result) in results.enumerated() {
            group.enter()
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                defer { group.leave() }
                guard let data, let image = displayImage(from: data) else { return }
                let meta = metadata(from: data)
                lock.lock()
                picked[index] = Picked(image: image, coordinate: meta.coordinate, takenAt: meta.takenAt)
                lock.unlock()
            }
        }
        group.notify(queue: .global(qos: .userInitiated)) { finish() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish() }
    }

    /// GPS position and capture time from an image file's properties.
    static func metadata(from data: Data) -> (coordinate: CLLocationCoordinate2D?, takenAt: Date?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return (nil, nil) }
        return (coordinate(fromGPS: props[kCGImagePropertyGPSDictionary] as? [CFString: Any]),
                takenAt(exif: props[kCGImagePropertyExifDictionary] as? [CFString: Any],
                        tiff: props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]))
    }

    static func coordinate(fromGPS gps: [CFString: Any]?) -> CLLocationCoordinate2D? {
        guard let gps,
              var lat = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              var lon = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" { lat = -abs(lat) }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" { lon = -abs(lon) }
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        guard CLLocationCoordinate2DIsValid(c), !(lat == 0 && lon == 0) else { return nil }
        return c
    }

    /// "2026:10:04 14:10:05" plus "-04:00" when the camera recorded it;
    /// without an offset, the phone's time zone.
    static func takenAt(exif: [CFString: Any]?, tiff: [CFString: Any]?) -> Date? {
        let stamp = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        guard let stamp else { return nil }
        let offset = (exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String) ?? (exif?[kCGImagePropertyExifOffsetTime] as? String)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if let offset {
            f.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            if let date = f.date(from: stamp + offset) { return date }
        }
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = .current
        return f.date(from: stamp)
    }

    /// A ≤2048 px image, rotated upright, decoded without its metadata.
    static func displayImage(from data: Data, maxPixels: Int = 2048) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A one-shot picker delegate as a closure, for screens that don't adopt
/// PHPickerViewControllerDelegate themselves. Keeps itself alive until used.
final class PhotoPickerRelay: NSObject, PHPickerViewControllerDelegate {
    private static var current: PhotoPickerRelay?
    private let onPick: ([PHPickerResult]) -> Void

    private init(_ onPick: @escaping ([PHPickerResult]) -> Void) { self.onPick = onPick }

    static func present(from host: UIViewController, configuration: PHPickerConfiguration,
                        onPick: @escaping ([PHPickerResult]) -> Void) {
        let relay = PhotoPickerRelay(onPick)
        current = relay
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = relay
        host.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        Self.current = nil
        let onPick = self.onPick
        // Hand over once the picker is gone: presenting a loading box over a
        // picker that's still leaving is what left one stuck on screen
        picker.dismiss(animated: true) {
            if !results.isEmpty { onPick(results) }
        }
    }
}
