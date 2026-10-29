import Foundation

/// Moment (video/photo) endpoints: a user's moments, the reels feed,
/// delete, visibility, likes and views. Uploads live in VideoUploadService.
final class VideoService {
    static let shared = VideoService()

    private let api: APIClient

    init(api: APIClient = APIService.shared) {
        self.api = api
    }

    // MARK: - Videos
    
    func getUserVideos(userId: String, limit: Int = 20, offset: Int = 0, completion: @escaping (Result<VideosResponse, APIError>) -> Void) {
        let queryParams = "?limit=\(limit)&offset=\(offset)"
        api.request(
            endpoint: "videos/user/\(userId)\(queryParams)",
            method: .get,
            requiresAuth: true // the server shows private/network moments only to viewers it can identify (security audit 2026-10-01)
        ) { (result: Result<VideosResponse, APIError>) in
            completion(result)
        }
    }
    
    func getUserReels(userId: String, limit: Int = 20, offset: Int = 0, completion: @escaping (Result<VideosResponse, APIError>) -> Void) {
        let queryParams = "?limit=\(limit)&offset=\(offset)"
        api.request(
            endpoint: "videos/reels/user/\(userId)\(queryParams)",
            method: .get,
            requiresAuth: true
        ) { (result: Result<VideosResponse, APIError>) in
            completion(result)
        }
    }
    
    func getReelsFeed(limit: Int = 20, offset: Int = 0, completion: @escaping (Result<VideosResponse, APIError>) -> Void) {
        let queryParams = "?limit=\(limit)&offset=\(offset)"
        api.request(
            endpoint: "videos/reels/feed\(queryParams)",
            method: .get,
            requiresAuth: true
        ) { (result: Result<VideosResponse, APIError>) in
            completion(result)
        }
    }
    
    func deleteVideo(videoId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        api.request(
            endpoint: "videos/\(videoId)",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Change a moment's privacy. Reuses PUT /videos/:id (owner-checked server-side).
    func updateVideoVisibility(videoId: String, visibility: VideoVisibility, completion: @escaping (Result<Void, APIError>) -> Void) {
        api.request(
            endpoint: "videos/\(videoId)",
            method: .put,
            body: ["visibility": visibility.rawValue],
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func likeReel(videoId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        api.request(
            endpoint: "videos/reels/\(videoId)/like",
            method: .post,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func unlikeReel(videoId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        api.request(
            endpoint: "videos/reels/\(videoId)/like",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func trackReelView(videoId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        api.request(
            endpoint: "videos/reels/\(videoId)/view",
            method: .post,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
