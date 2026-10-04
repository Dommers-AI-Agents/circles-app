import UIKit

/// Photos for a place that couldn't be uploaded yet — no signal, a dropped
/// request, a save that went ahead without waiting for them. They are kept
/// on the phone (Application Support, survives restarts) and added to the
/// place's photo library as soon as there is a connection.
///
/// Wes, 2026-10-04: "I don't want places to be saved and have no photos…
/// ensure the photos are added later if needed once a signal is available."
/// A queued photo is never given up on (user data is never pruned); only a
/// place that no longer exists drops its queue.
final class PlacePhotoOutbox {
    static let shared = PlacePhotoOutbox()

    struct Item: Codable, Equatable {
        let id: String
        /// The save the photo was taken for, and its place record when known
        let placeId: String
        let globalPlaceId: String?
        let placeName: String
        let file: String
        let createdAt: Date
        var attempts: Int
    }

    private let queue = DispatchQueue(label: "PlacePhotoOutbox")
    private var items: [Item] = []
    private var isDraining = false
    private var observers: [NSObjectProtocol] = []

    private let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PlacePhotoOutbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private init() {
        items = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
        let center = NotificationCenter.default
        // Signal back → send what's waiting
        observers.append(center.addObserver(forName: .networkReachabilityDidChange, object: nil, queue: .main) { [weak self] note in
            if (note.userInfo?[NetworkMonitor.isConnectedKey] as? Bool) ?? NetworkMonitor.shared.isConnected { self?.drain() }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.drain()
        })
    }

    // MARK: - Queue

    /// Keep these photos for `place` and send them when possible.
    func add(_ images: [UIImage], to place: Place) {
        let newItems: [Item] = images.compactMap { image in
            guard let data = Self.jpeg(image) else { return nil }
            let id = UUID().uuidString
            let file = "\(id).jpg"
            do { try data.write(to: directory.appendingPathComponent(file), options: .atomic) } catch { return nil }
            return Item(id: id, placeId: place.id, globalPlaceId: place.globalPlaceId, placeName: place.name,
                        file: file, createdAt: Date(), attempts: 0)
        }
        guard !newItems.isEmpty else { return }
        queue.sync {
            items.append(contentsOf: newItems)
            persist()
        }
        Logger.debug("📮 PlacePhotoOutbox: \(newItems.count) photo(s) waiting for \(place.name)")
        drain()
    }

    /// Whether a photo of this save (or its place record) is still waiting —
    /// the background Look Around pass leaves those places alone.
    func hasPending(placeId: String) -> Bool {
        queue.sync { items.contains { $0.placeId == placeId || $0.globalPlaceId == placeId } }
    }

    var pendingCount: Int { queue.sync { items.count } }

    // MARK: - Sending

    /// Send everything waiting, one at a time. Stops at the first network
    /// failure (the next reconnect or launch picks up from there).
    func drain() {
        DispatchQueue.main.async {
            guard !self.isDraining, AuthService.shared.isLoggedIn, NetworkMonitor.shared.isConnected else { return }
            guard let first = self.queue.sync(execute: { self.items.first }) else { return }
            self.isDraining = true
            self.send(first)
        }
    }

    private func send(_ item: Item) {
        let fileURL = directory.appendingPathComponent(item.file)
        guard let data = try? Data(contentsOf: fileURL) else {
            finish(item, removed: true) // the file is gone — nothing left to send
            return
        }
        PlaceService.shared.uploadImage(data) { [weak self] upload in
            guard let self else { return }
            guard case .success(let url) = upload else { return self.stop(item) }
            GlobalPlaceService.shared.uploadPlaceMedia(placeId: item.globalPlaceId ?? item.placeId,
                                                       mediaType: "photo", mediaUrl: url,
                                                       title: item.placeName, description: "") { attached in
                switch attached {
                case .success:
                    self.finish(item, removed: true)
                case .failure(let error):
                    // The place was unsaved/deleted meanwhile: nowhere to put it
                    if case APIError.httpError(404, _)? = error as? APIError { self.finish(item, removed: true) }
                    else { self.stop(item) }
                }
            }
        }
    }

    private func finish(_ item: Item, removed: Bool) {
        queue.sync {
            items.removeAll { $0.id == item.id }
            persist()
        }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.file))
        Logger.debug("📮 PlacePhotoOutbox: photo for \(item.placeName) \(removed ? "sent" : "dropped")")
        NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
        DispatchQueue.main.async {
            self.isDraining = false
            self.drain()
        }
    }

    /// Keep it and try again on the next reconnect/launch.
    private func stop(_ item: Item) {
        queue.sync {
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].attempts += 1 }
            persist()
        }
        DispatchQueue.main.async { self.isDraining = false }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexURL, options: .atomic) }
    }

    /// Stored as a JPEG no larger than the app uploads anyway.
    private static func jpeg(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 2048
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image.jpegData(compressionQuality: 0.8) }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
