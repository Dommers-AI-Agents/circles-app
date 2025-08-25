import Foundation
import UIKit
import AVFoundation

class VideoUploadService {
    static let shared = VideoUploadService()
    
    private init() {}
    
    // MARK: - Upload Video
    
    func uploadVideo(
        previewVideo: CompressedVideo,
        fullVideo: CompressedVideo,
        place: Place,
        title: String? = nil,
        description: String? = nil,
        completion: @escaping (Result<PlaceVideo, Error>) -> Void
    ) {
        // Step 1: Initiate upload with backend
        // Read video data from URL
        guard let fullVideoData = try? Data(contentsOf: fullVideo.url),
              let previewVideoData = try? Data(contentsOf: previewVideo.url) else {
            completion(.failure(APIError.invalidResponse))
            return
        }
        
        initiateUpload(
            place: place,
            duration: fullVideo.duration,
            fileSize: Int(fullVideo.sizeInBytes),
            title: title,
            description: description
        ) { [weak self] result in
            switch result {
            case .success(let uploadInfo):
                // Step 2: Upload files to storage
                self?.uploadFiles(
                    videoId: uploadInfo.videoId,
                    uploadUrls: uploadInfo.uploadUrls,
                    previewVideoData: previewVideoData,
                    fullVideoData: fullVideoData,
                    fullVideoUrl: fullVideo.url
                ) { uploadResult in
                    switch uploadResult {
                    case .success:
                        // Step 3: Complete upload with backend
                        self?.completeUpload(
                            videoId: uploadInfo.videoId,
                            storagePaths: uploadInfo.storagePaths,
                            originalSize: Int(fullVideo.sizeInBytes)
                        ) { completeResult in
                            switch completeResult {
                            case .success(let video):
                                // Poll for processing completion before returning success
                                self?.waitForVideoProcessing(videoId: uploadInfo.videoId) { processingResult in
                                    switch processingResult {
                                    case .success:
                                        completion(.success(video))
                                    case .failure(let error):
                                        print("⚠️ Video processing check failed: \(error)")
                                        // Still return success but video might show as processing
                                        completion(.success(video))
                                    }
                                }
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func initiateUpload(
        place: Place,
        duration: TimeInterval,
        fileSize: Int,
        title: String?,
        description: String?,
        completion: @escaping (Result<VideoUploadInfo, Error>) -> Void
    ) {
        let body: [String: Any] = [
            "placeId": place.id,
            "placeName": place.name,
            "duration": Int(duration),
            "fileSize": fileSize,
            "title": title ?? "Video at \(place.name)",
            "description": description ?? "",
            "visibility": "public",
            "tags": []
        ]
        
        APIService.shared.request(
            endpoint: "videos/initiate",
            method: .post,
            body: body
        ) { (result: Result<VideoUploadInitResponse, APIError>) in
            switch result {
            case .success(let response):
                if response.success {
                    let data = response.data
                    let uploadInfo = VideoUploadInfo(
                        videoId: data.videoId,
                        uploadUrls: VideoUploadUrls(
                            video: data.uploadUrls.video,
                            preview: data.uploadUrls.preview,
                            thumbnail: data.uploadUrls.thumbnail
                        ),
                        storagePaths: VideoStoragePaths(
                            video: data.storagePaths.video,
                            preview: data.storagePaths.preview,
                            thumbnail: data.storagePaths.thumbnail
                        )
                    )
                    completion(.success(uploadInfo))
                } else {
                    completion(.failure(APIError.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func uploadFiles(
        videoId: String,
        uploadUrls: VideoUploadUrls,
        previewVideoData: Data,
        fullVideoData: Data,
        fullVideoUrl: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let uploadGroup = DispatchGroup()
        var uploadError: Error?
        
        // Upload preview video
        uploadGroup.enter()
        uploadToSignedUrl(data: previewVideoData, signedUrl: uploadUrls.preview) { error in
            if let error = error {
                uploadError = error
                print("Failed to upload preview video: \(error)")
            }
            uploadGroup.leave()
        }
        
        // Upload full video
        uploadGroup.enter()
        uploadToSignedUrl(data: fullVideoData, signedUrl: uploadUrls.video) { error in
            if let error = error {
                uploadError = error
                print("Failed to upload full video: \(error)")
            }
            uploadGroup.leave()
        }
        
        // Generate and upload thumbnail
        if let thumbnail = generateThumbnail(from: fullVideoUrl) {
            uploadGroup.enter()
            if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
                print("📤 VideoUploadService: Uploading thumbnail - Size: \(thumbnailData.count) bytes")
                print("   - Thumbnail URL: \(uploadUrls.thumbnail.suffix(100))")
                uploadToSignedUrl(data: thumbnailData, signedUrl: uploadUrls.thumbnail) { error in
                    if let error = error {
                        print("❌ VideoUploadService: Failed to upload thumbnail: \(error)")
                        // Don't fail the whole upload if thumbnail fails
                    } else {
                        print("✅ VideoUploadService: Thumbnail uploaded successfully")
                    }
                    uploadGroup.leave()
                }
            } else {
                print("⚠️ VideoUploadService: Failed to convert thumbnail to JPEG data")
                uploadGroup.leave()
            }
        } else {
            print("⚠️ VideoUploadService: No thumbnail generated")
        }
        
        uploadGroup.notify(queue: .main) {
            if let error = uploadError {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    private func uploadToSignedUrl(data: Data, signedUrl: String, completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: signedUrl) else {
            completion(APIError.invalidURL)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    completion(nil)
                } else {
                    completion(APIError.serverError)
                }
            } else {
                completion(APIError.invalidResponse)
            }
        }
        
        task.resume()
    }
    
    private func completeUpload(
        videoId: String,
        storagePaths: VideoStoragePaths,
        originalSize: Int,
        completion: @escaping (Result<PlaceVideo, Error>) -> Void
    ) {
        let body: [String: Any] = [
            "storagePaths": [
                "video": storagePaths.video,
                "preview": storagePaths.preview,
                "thumbnail": storagePaths.thumbnail
            ],
            "originalSize": originalSize,
            "compressionRatio": 0.5 // Approximate based on our compression settings
        ]
        
        APIService.shared.request(
            endpoint: "videos/\(videoId)/complete",
            method: .post,
            body: body
        ) { (result: Result<VideoCompleteResponse, APIError>) in
            switch result {
            case .success(let response):
                if response.success, let video = response.data {
                    completion(.success(video))
                } else {
                    completion(.failure(APIError.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func generateThumbnail(from videoUrl: URL) -> UIImage? {
        print("🎬 VideoUploadService: Generating thumbnail from: \(videoUrl.lastPathComponent)")
        
        // Use AVAssetImageGenerator to create thumbnail
        let asset = AVAsset(url: videoUrl)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 0, preferredTimescale: 1)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let thumbnail = UIImage(cgImage: cgImage)
            print("✅ VideoUploadService: Thumbnail generated - Size: \(thumbnail.size)")
            return thumbnail
        } catch {
            print("❌ VideoUploadService: Error generating thumbnail: \(error)")
            return nil
        }
    }
    
    // MARK: - Video Processing Status
    
    private func waitForVideoProcessing(videoId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let maxAttempts = 30 // 30 attempts with 2-second intervals = 60 seconds max
        var attempts = 0
        
        func checkStatus() {
            attempts += 1
            
            APIService.shared.request(
                endpoint: "videos/\(videoId)/status",
                method: .get,
                body: nil
            ) { (result: Result<VideoStatusResponse, APIError>) in
                switch result {
                case .success(let response):
                    if response.success, let data = response.data {
                        if data.isReady {
                            // Processing complete
                            print("✅ Video \(videoId) processing completed")
                            completion(.success(()))
                            return
                        } else if data.uploadStatus == "error" {
                            // Processing failed
                            completion(.failure(APIError.processingFailed))
                            return
                        } else if attempts < maxAttempts {
                            // Still processing, wait and check again
                            print("📹 Video \(videoId) still processing... (\(attempts)/\(maxAttempts))")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                checkStatus()
                            }
                        } else {
                            // Timeout - processing took too long
                            print("⏰ Video \(videoId) processing timeout after \(maxAttempts) attempts")
                            completion(.failure(APIError.processingTimeout))
                        }
                    } else {
                        completion(.failure(APIError.invalidResponse))
                    }
                case .failure(let error):
                    if attempts < maxAttempts {
                        // Retry on network error
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            checkStatus()
                        }
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }
        
        // Start checking status
        checkStatus()
    }
}

// MARK: - Response Models

struct VideoUploadInfo {
    let videoId: String
    let uploadUrls: VideoUploadUrls
    let storagePaths: VideoStoragePaths
}

struct VideoUploadUrls {
    let video: String
    let preview: String
    let thumbnail: String
}

struct VideoStoragePaths {
    let video: String
    let preview: String
    let thumbnail: String
}

struct VideoCompleteResponse: Codable {
    let success: Bool
    let data: PlaceVideo?
}

struct VideoStatusResponse: Codable {
    let success: Bool
    let data: VideoStatusData?
    
    struct VideoStatusData: Codable {
        let videoId: String
        let uploadStatus: String
        let uploadProgress: Int
        let processingCompleted: String?
        let isReady: Bool
    }
}