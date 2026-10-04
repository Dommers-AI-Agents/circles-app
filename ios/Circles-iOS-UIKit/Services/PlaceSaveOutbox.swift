import UIKit

/// Thrown by PlaceService when an Add Place save couldn't reach the server
/// and was kept on the phone instead: "Weak signal – your place will be
/// saved when you're back online" (Wes, 2026-10-04).
struct PlaceSaveQueued: Error {
    let entryId: String
    let placeName: String
}

/// Add Place saves made without a usable signal. The request (and the
/// user's own photo, if it hadn't uploaded) is kept in Application Support
/// and sent when there's a connection — on reconnect, foreground or launch.
///
/// If the first attempt actually reached the server before the signal
/// dropped, the resend gets the server's "already saved" answer and the
/// entry is simply closed: never a second copy.
final class PlaceSaveOutbox {
    static let shared = PlaceSaveOutbox()

    struct Entry: Codable {
        let id: String
        let placeName: String
        /// The JSON body POST /places was going to send
        let body: Data
        /// The user's own photo, when it hadn't uploaded yet
        var imageFile: String?
        let createdAt: Date
        var attempts: Int
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var isDraining = false
    private var observers: [NSObjectProtocol] = []

    private let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PlaceSaveOutbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private init() {
        entries = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .networkReachabilityDidChange, object: nil, queue: .main) { [weak self] note in
            if (note.userInfo?[NetworkMonitor.isConnectedKey] as? Bool) ?? NetworkMonitor.shared.isConnected { self?.drain() }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.drain()
        })
    }

    var pendingCount: Int { locked { entries.count } }

    /// Keep a save for later. Returns the entry id (nil if it couldn't be stored).
    func enqueue(body: [String: Any], placeName: String) -> String? {
        guard JSONSerialization.isValidJSONObject(body), let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        let entry = Entry(id: UUID().uuidString, placeName: placeName, body: data, imageFile: nil, createdAt: Date(), attempts: 0)
        locked {
            entries.append(entry)
            persist()
        }
        Logger.debug("📮 PlaceSaveOutbox: kept \(placeName) for when there's a signal")
        return entry.id
    }

    /// The user's own photo for a kept save; added to the place once it's saved.
    func attachImage(_ image: UIImage, toEntry id: String) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let file = "\(id).jpg"
        guard (try? data.write(to: directory.appendingPathComponent(file), options: .atomic)) != nil else { return }
        locked {
            if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].imageFile = file }
            persist()
        }
    }

    // MARK: - Sending

    func drain() {
        DispatchQueue.main.async {
            guard !self.isDraining, AuthService.shared.isLoggedIn, NetworkMonitor.shared.isConnected,
                  let entry = self.locked({ self.entries.first }) else { return }
            self.isDraining = true
            self.send(entry)
        }
    }

    private func send(_ entry: Entry) {
        guard let body = (try? JSONSerialization.jsonObject(with: entry.body)) as? [String: Any] else {
            return close(entry, message: nil)
        }
        PlaceService.shared.sendKeptPlace(body: body) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let place):
                    if let file = entry.imageFile, let image = UIImage(contentsOfFile: self.directory.appendingPathComponent(file).path) {
                        PlacePhotoOutbox.shared.add([image], to: place)
                    }
                    NotificationCenter.default.post(name: Notification.Name("PlaceAddedToCircle"), object: nil,
                                                    userInfo: ["circleId": place.circleId ?? "", "place": place])
                    ImportPhotoQueue.shared.kick()
                    self.close(entry, message: "Saved \(entry.placeName)")
                case .failure(let error) where NetworkErrorClassifier.isConnectivityFailure(error):
                    // Still no signal: keep it for the next reconnect
                    self.locked {
                        if let index = self.entries.firstIndex(where: { $0.id == entry.id }) { self.entries[index].attempts += 1 }
                        self.persist()
                    }
                    self.isDraining = false
                case .failure(let error):
                    if PlaceDuplicate.from(error) != nil {
                        self.close(entry, message: "\(entry.placeName) was already saved")
                    } else {
                        let reason = (error as? APIError)?.serverMessage ?? error.localizedDescription
                        Logger.error("📮 PlaceSaveOutbox: kept save of \(entry.placeName) refused after \(entry.attempts) attempt(s): \(reason)")
                        self.close(entry, message: "Couldn't save \(entry.placeName): \(reason)")
                    }
                }
            }
        }
    }

    /// Done with an entry (saved, already saved, or refused): drop it and say so.
    private func close(_ entry: Entry, message: String?) {
        locked {
            entries.removeAll { $0.id == entry.id }
            persist()
        }
        if let file = entry.imageFile { try? FileManager.default.removeItem(at: directory.appendingPathComponent(file)) }
        if let message { Self.announce(message) }
        NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
        isDraining = false
        drain()
    }

    private static func announce(_ message: String) {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        AlertPresenter.showBriefMessage(message, from: top, duration: 2)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: indexURL, options: .atomic) }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}
