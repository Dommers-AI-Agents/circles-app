import Foundation
import UIKit
import AVFoundation

// MARK: - Processed Media Types
struct ProcessedPhoto {
    let image: UIImage
    let data: Data
    let sizeInBytes: Int
    let compressionRatio: Float
    let dimensions: CGSize
}

struct ProcessedVideo {
    let url: URL
    let thumbnail: UIImage
    let thumbnailData: Data
    let sizeInBytes: Int64
    let duration: TimeInterval
    let compressionRatio: Float
}

// MARK: - Media Processing Service
class MediaProcessingService {
    
    static let shared = MediaProcessingService()
    
    private init() {}
    
    // MARK: - Photo Processing
    
    /// Process and compress photo using Moments standards
    /// - Resizes to max 1080px dimension
    /// - Compresses with 0.7 JPEG quality
    func processPhoto(
        _ image: UIImage,
        completion: @escaping (Result<ProcessedPhoto, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let originalSize = image.jpegData(compressionQuality: 1.0)?.count ?? 0
                
                // Resize image to max 1080px dimension (same as Moments)
                let resizedImage = self.resizeImage(image, maxDimension: 1080)
                
                // Compress with 0.7 quality (same as Moments)
                guard let compressedData = resizedImage.jpegData(compressionQuality: 0.7) else {
                    DispatchQueue.main.async {
                        completion(.failure(MediaProcessingError.compressionFailed))
                    }
                    return
                }
                
                let compressionRatio: Float = originalSize > 0 ? 
                    Float(compressedData.count) / Float(originalSize) : 1.0
                
                let processedPhoto = ProcessedPhoto(
                    image: resizedImage,
                    data: compressedData,
                    sizeInBytes: compressedData.count,
                    compressionRatio: compressionRatio,
                    dimensions: resizedImage.size
                )
                
                DispatchQueue.main.async {
                    completion(.success(processedPhoto))
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Video Processing
    
    /// Process and compress video using Moments standards
    /// - 15 second maximum duration
    /// - 720p resolution, 500kbps bitrate
    /// - Generates thumbnail
    func processVideo(
        at url: URL,
        progress: @escaping (Double) -> Void = { _ in },
        completion: @escaping (Result<ProcessedVideo, Error>) -> Void
    ) {
        // Use the existing VideoCompressionService with preview quality (same as Moments)
        VideoCompressionService.shared.compressVideo(
            inputURL: url,
            quality: .preview, // Same quality as Moments
            progress: progress
        ) { [weak self] result in
            switch result {
            case .success(let compressedVideo):
                // Generate thumbnail
                self?.generateThumbnail(from: compressedVideo.url) { thumbnailResult in
                    switch thumbnailResult {
                    case .success(let (thumbnail, thumbnailData)):
                        let processedVideo = ProcessedVideo(
                            url: compressedVideo.url,
                            thumbnail: thumbnail,
                            thumbnailData: thumbnailData,
                            sizeInBytes: compressedVideo.sizeInBytes,
                            duration: compressedVideo.duration,
                            compressionRatio: compressedVideo.compressionRatio
                        )
                        completion(.success(processedVideo))
                        
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generate thumbnail from video (same approach as Moments)
    private func generateThumbnail(
        from videoURL: URL,
        completion: @escaping (Result<(UIImage, Data), Error>) -> Void
    ) {
        DispatchQueue.global(qos: .background).async {
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 300, height: 300)
            
            let time = CMTime(seconds: 1.0, preferredTimescale: 600)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                
                // Compress thumbnail with 0.7 quality (same as Moments)
                guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) else {
                    DispatchQueue.main.async {
                        completion(.failure(MediaProcessingError.thumbnailGenerationFailed))
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    completion(.success((thumbnail, thumbnailData)))
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Resize image to fit within max dimension while maintaining aspect ratio
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            // Landscape
            newSize = CGSize(width: min(maxDimension, size.width), height: min(maxDimension, size.width) / aspectRatio)
        } else {
            // Portrait or square
            newSize = CGSize(width: min(maxDimension, size.height) * aspectRatio, height: min(maxDimension, size.height))
        }
        
        // Don't upscale images
        if newSize.width > size.width || newSize.height > size.height {
            return image
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    /// Get original file size for compression ratio calculation
    private func getOriginalFileSize(for image: UIImage) -> Int {
        return image.jpegData(compressionQuality: 1.0)?.count ?? 0
    }
}

// MARK: - Media Processing Errors
enum MediaProcessingError: LocalizedError {
    case compressionFailed
    case thumbnailGenerationFailed
    case invalidInput
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress media"
        case .thumbnailGenerationFailed:
            return "Failed to generate video thumbnail"
        case .invalidInput:
            return "Invalid media input"
        case .unknown:
            return "An unknown processing error occurred"
        }
    }
}