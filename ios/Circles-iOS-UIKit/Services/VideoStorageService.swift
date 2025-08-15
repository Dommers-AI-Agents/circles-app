import Foundation
import AVFoundation

class VideoStorageService {
    static let shared = VideoStorageService()
    
    private let mediaCacheService = MediaCacheService.shared
    private let downloadQueue = DispatchQueue(label: "com.circles.video.download", attributes: .concurrent)
    private var activeDownloads: Set<String> = []
    private let downloadsLock = NSLock()
    
    private init() {}
    
    // MARK: - Video Caching
    
    func cacheVideo(from url: String, isUserContent: Bool, completion: @escaping (Bool) -> Void) {
        // Check if already downloading
        downloadsLock.lock()
        if activeDownloads.contains(url) {
            downloadsLock.unlock()
            print("⚠️ VideoStorageService: Already downloading video from \(url)")
            completion(false)
            return
        }
        activeDownloads.insert(url)
        downloadsLock.unlock()
        
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard let videoURL = URL(string: url) else {
                print("❌ VideoStorageService: Invalid URL: \(url)")
                self.removeFromActiveDownloads(url)
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            // Create download task
            let task = URLSession.shared.dataTask(with: videoURL) { [weak self] data, response, error in
                defer {
                    self?.removeFromActiveDownloads(url)
                }
                
                if let error = error {
                    print("❌ VideoStorageService: Download error: \(error)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                
                guard let data = data else {
                    print("❌ VideoStorageService: No data received")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                
                // Determine user ID for permanent storage
                let userId = isUserContent ? AuthService.shared.getUserId() : nil
                
                // Cache the video data
                _ = self?.mediaCacheService.cacheMedia(
                    data: data,
                    url: url,
                    mediaType: .video,
                    userId: userId,
                    isPermanent: isUserContent
                )
                
                print("✅ VideoStorageService: Cached video (\(data.count / 1024 / 1024)MB) from \(url)")
                
                DispatchQueue.main.async {
                    completion(true)
                }
            }
            
            task.resume()
        }
    }
    
    func retrieveVideoURL(for urlString: String, completion: @escaping (URL?) -> Void) {
        // First check if we have it cached
        mediaCacheService.retrieveMedia(for: urlString) { data in
            if let data = data {
                // Create temporary file URL for AVPlayer
                let tempURL = self.createTemporaryVideoURL(from: data)
                print("✅ VideoStorageService: Retrieved video from cache")
                completion(tempURL)
            } else {
                // Return original URL for streaming
                completion(URL(string: urlString))
            }
        }
    }
    
    // MARK: - Batch Operations
    
    func preloadVideos(urls: [String], isUserContent: Bool) {
        for url in urls {
            cacheVideo(from: url, isUserContent: isUserContent) { _ in
                // Silent preload
            }
        }
    }
    
    func cacheUserVideos(_ videos: [PlaceVideo]) {
        print("📥 VideoStorageService: Caching \(videos.count) user videos")
        
        for video in videos {
            // Cache video URL
            if let videoUrl = video.videoUrl {
                cacheVideo(from: videoUrl, isUserContent: true) { success in
                    if success {
                        print("✅ Cached full video: \(video.title)")
                    }
                }
            }
            
            // Cache preview URL
            if let previewUrl = video.previewUrl {
                cacheVideo(from: previewUrl, isUserContent: true) { success in
                    if success {
                        print("✅ Cached preview video: \(video.title)")
                    }
                }
            }
            
            // Cache thumbnail
            if let thumbnailUrl = video.thumbnailUrl {
                downloadAndCacheThumbnail(from: thumbnailUrl, isUserContent: true)
            }
        }
    }
    
    func cacheNetworkVideos(_ videos: [PlaceVideo]) {
        print("📥 VideoStorageService: Caching \(videos.count) network videos")
        
        // Only cache thumbnails and preview videos for network content
        for video in videos {
            // Cache thumbnail for quick display
            if let thumbnailUrl = video.thumbnailUrl {
                downloadAndCacheThumbnail(from: thumbnailUrl, isUserContent: false)
            }
            
            // Cache preview video (lower quality)
            if let previewUrl = video.previewUrl {
                cacheVideo(from: previewUrl, isUserContent: false) { success in
                    if success {
                        print("✅ Cached network preview: \(video.title)")
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTemporaryVideoURL(from data: Data) -> URL? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".mp4"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("❌ VideoStorageService: Failed to create temporary file: \(error)")
            return nil
        }
    }
    
    private func downloadAndCacheThumbnail(from urlString: String, isUserContent: Bool) {
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            if let error = error {
                print("❌ VideoStorageService: Thumbnail download error: \(error)")
                return
            }
            
            guard let data = data else { return }
            
            let userId = isUserContent ? AuthService.shared.getUserId() : nil
            _ = self?.mediaCacheService.cacheMedia(
                data: data,
                url: urlString,
                mediaType: .thumbnail,
                userId: userId,
                isPermanent: isUserContent
            )
            
            print("✅ VideoStorageService: Cached thumbnail from \(urlString)")
        }.resume()
    }
    
    private func removeFromActiveDownloads(_ url: String) {
        downloadsLock.lock()
        activeDownloads.remove(url)
        downloadsLock.unlock()
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        // Clear temporary video files
        let tempDirectory = FileManager.default.temporaryDirectory
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in tempFiles where file.pathExtension == "mp4" {
                try FileManager.default.removeItem(at: file)
            }
            print("✅ VideoStorageService: Cleared temporary video files")
        } catch {
            print("❌ VideoStorageService: Failed to clear temp files: \(error)")
        }
    }
}