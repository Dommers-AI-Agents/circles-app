import Photos
import UIKit

/// Where and when every photo in the library was taken, read on the phone
/// and cached (Caches), so "your photos from here" and "build a circle from
/// my photos" answer instantly (Wes, 2026-10-09). Nothing leaves the phone
/// except a photo the person chooses to add. Asks for library access only
/// when a photo feature is used.
final class PhotoLibraryIndex {
    static let shared = PhotoLibraryIndex()

    typealias Shot = PhotoLibraryMath.Shot

    private let queue = DispatchQueue(label: "photo-library-index", qos: .userInitiated)
    private var cached: [Shot]?
    private var newest: Date?
    private let imageManager = PHCachingImageManager()

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("photo-library-index-v1.json")
    }

    // MARK: - Access

    var status: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    var canRead: Bool { status == .authorized || status == .limited }
    var mayAsk: Bool { status == .notDetermined }

    /// Asks once; completion on main with whether the library can be read.
    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        guard !canRead else { return completion(true) }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { completion(status == .authorized || status == .limited) }
        }
    }

    // MARK: - Shots

    /// Every located photo; the first call reads the library (seconds for a
    /// big one), later calls only add what's new. Completion on main.
    func shots(_ completion: @escaping ([Shot]) -> Void) {
        guard canRead else { return completion([]) }
        queue.async { [weak self] in
            guard let self else { return }
            if self.cached == nil { self.loadCache() }
            let fresh = self.readLibrary(after: self.newest)
            if !fresh.isEmpty || self.cached == nil {
                let all = (self.cached ?? []) + fresh
                self.cached = all
                self.newest = all.map(\.date).max()
                self.saveCache()
            }
            let result = self.cached ?? []
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Photos taken within ~75 m of a place, newest first. Completion on main.
    func shots(near coordinate: CLLocationCoordinate2D, limit: Int = 24, _ completion: @escaping ([Shot]) -> Void) {
        shots { all in completion(PhotoLibraryMath.near(all, center: coordinate, limit: limit)) }
    }

    /// The user's own albums with located photos, for "From an album".
    func albums() -> [(title: String, collection: PHAssetCollection)] {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var out: [(String, PHAssetCollection)] = []
        result.enumerateObjects { collection, _, _ in
            if collection.estimatedAssetCount != 0, let title = collection.localizedTitle { out.append((title, collection)) }
        }
        return out.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    /// Located photos in one album. Completion on main.
    func shots(in album: PHAssetCollection, _ completion: @escaping ([Shot]) -> Void) {
        queue.async {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let assets = PHAsset.fetchAssets(in: album, options: options)
            var out: [Shot] = []
            assets.enumerateObjects { asset, _, _ in if let shot = Self.shot(asset) { out.append(shot) } }
            DispatchQueue.main.async { completion(out) }
        }
    }

    // MARK: - Images

    /// A thumbnail (or full-size, for uploading) for one photo; may fetch
    /// from iCloud. Completion on main, nil when the photo is gone.
    func image(for id: String, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return completion(nil)
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// The ≤2048 px image used when a photo is added to a place.
    func uploadImage(for id: String, completion: @escaping (UIImage?) -> Void) {
        image(for: id, size: CGSize(width: 2048, height: 2048), completion: completion)
    }

    // MARK: - Reading

    private func readLibrary(after date: Date?) -> [Shot] {
        let options = PHFetchOptions()
        var predicates = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]
        if let date { predicates.append(NSPredicate(format: "creationDate > %@", date as NSDate)) }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: options)
        var out: [Shot] = []
        out.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in if let shot = Self.shot(asset) { out.append(shot) } }
        return out
    }

    private static func shot(_ asset: PHAsset) -> Shot? {
        guard let location = asset.location, let date = asset.creationDate,
              CLLocationCoordinate2DIsValid(location.coordinate),
              !(location.coordinate.latitude == 0 && location.coordinate.longitude == 0) else { return nil }
        return Shot(id: asset.localIdentifier, lat: location.coordinate.latitude, lng: location.coordinate.longitude, date: date)
    }

    private func loadCache() {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let shots = try? JSONDecoder().decode([Shot].self, from: data) else { return }
        cached = shots
        newest = shots.map(\.date).max()
    }

    private func saveCache() {
        guard let url = cacheURL, let cached, let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
