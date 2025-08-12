import Foundation
import AVFoundation
import UIKit

// MARK: - Compressed Video Model
struct CompressedVideo {
    let url: URL
    let sizeInBytes: Int64
    let duration: TimeInterval
    let compressionRatio: Float
    let thumbnail: UIImage?
}

// MARK: - Video Compression Service
class VideoCompressionService {
    
    static let shared = VideoCompressionService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Compress video with specified quality
    func compressVideo(
        inputURL: URL,
        quality: VideoQuality,
        progress: @escaping (Double) -> Void = { _ in },
        completion: @escaping (Result<CompressedVideo, Error>) -> Void
    ) {
        // Create unique output URL
        let outputURL = getOutputURL(for: quality)
        
        // Get original file size
        let originalSize = getFileSize(at: inputURL)
        
        // Create asset and check if it's valid
        let asset = AVAsset(url: inputURL)
        
        Task {
            do {
                // Check video duration
                let duration = try await asset.load(.duration)
                let durationInSeconds = CMTimeGetSeconds(duration)
                
                // Auto-trim videos longer than 15 seconds (for Moments feature)
                let maxDuration: TimeInterval = 15.0
                let finalDuration = min(durationInSeconds, maxDuration)
                
                // Get video track
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                    throw VideoCompressionError.noVideoTrack
                }
                
                // Create export session
                guard let exportSession = AVAssetExportSession(asset: asset, presetName: getPresetName(for: quality)) else {
                    throw VideoCompressionError.exportSessionCreationFailed
                }
                
                // Configure export session
                exportSession.outputURL = outputURL
                exportSession.outputFileType = .mp4
                exportSession.shouldOptimizeForNetworkUse = true
                
                // Set time range to trim video to 15 seconds if needed
                if durationInSeconds > maxDuration {
                    let startTime = CMTime.zero
                    let endTime = CMTime(seconds: maxDuration, preferredTimescale: duration.timescale)
                    exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)
                    print("📹 Auto-trimming video from \(durationInSeconds)s to \(maxDuration)s")
                }
                
                // Apply video settings
                let videoComposition = try await createVideoComposition(for: videoTrack, quality: quality)
                exportSession.videoComposition = videoComposition
                
                // Set up progress timer
                let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    progress(Double(exportSession.progress))
                }
                
                // Export video
                await exportSession.export()
                progressTimer.invalidate()
                
                // Check export status
                switch exportSession.status {
                case .completed:
                    // Get compressed file size
                    let compressedSize = getFileSize(at: outputURL)
                    let compressionRatio = Float(compressedSize) / Float(originalSize)
                    
                    // Generate thumbnail
                    let thumbnail = await generateThumbnail(from: outputURL)
                    
                    let compressedVideo = CompressedVideo(
                        url: outputURL,
                        sizeInBytes: compressedSize,
                        duration: finalDuration, // Use the trimmed duration
                        compressionRatio: compressionRatio,
                        thumbnail: thumbnail
                    )
                    
                    completion(.success(compressedVideo))
                    
                case .failed:
                    if let error = exportSession.error {
                        completion(.failure(error))
                    } else {
                        completion(.failure(VideoCompressionError.unknown))
                    }
                    
                case .cancelled:
                    completion(.failure(VideoCompressionError.cancelled))
                    
                default:
                    completion(.failure(VideoCompressionError.unknown))
                }
                
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    /// Compress video to both preview and full quality
    func compressVideoForUpload(
        inputURL: URL,
        progress: @escaping (Double) -> Void = { _ in },
        completion: @escaping (Result<(preview: CompressedVideo, full: CompressedVideo), Error>) -> Void
    ) {
        let group = DispatchGroup()
        var previewResult: Result<CompressedVideo, Error>?
        var fullResult: Result<CompressedVideo, Error>?
        
        // Compress preview quality
        group.enter()
        compressVideo(inputURL: inputURL, quality: .preview, progress: { p in
            progress(p * 0.5) // First half of progress
        }) { result in
            previewResult = result
            group.leave()
        }
        
        // Compress full quality
        group.enter()
        compressVideo(inputURL: inputURL, quality: .full, progress: { p in
            progress(0.5 + p * 0.5) // Second half of progress
        }) { result in
            fullResult = result
            group.leave()
        }
        
        // Wait for both compressions to complete
        group.notify(queue: .main) {
            guard let previewResult = previewResult,
                  let fullResult = fullResult else {
                completion(.failure(VideoCompressionError.unknown))
                return
            }
            
            switch (previewResult, fullResult) {
            case (.success(let preview), .success(let full)):
                completion(.success((preview: preview, full: full)))
            case (.failure(let error), _), (_, .failure(let error)):
                completion(.failure(error))
            }
        }
    }
    
    /// Generate thumbnail from video
    func generateThumbnail(from videoURL: URL) async -> UIImage? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 1280, height: 720)
        
        do {
            // Get thumbnail at 1 second mark or start
            let time = CMTime(seconds: 1, preferredTimescale: 600)
            let cgImage = try await imageGenerator.image(at: time).image
            return UIImage(cgImage: cgImage)
        } catch {
            // Try getting thumbnail at start
            do {
                let cgImage = try await imageGenerator.image(at: .zero).image
                return UIImage(cgImage: cgImage)
            } catch {
                print("Failed to generate thumbnail: \(error)")
                return nil
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func getOutputURL(for quality: VideoQuality) -> URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let outputPath = "\(documentsPath)/compressed_\(quality)_\(UUID().uuidString).mp4"
        return URL(fileURLWithPath: outputPath)
    }
    
    private func getFileSize(at url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    private func getPresetName(for quality: VideoQuality) -> String {
        switch quality {
        case .preview:
            return AVAssetExportPresetMediumQuality
        case .full:
            return AVAssetExportPresetHighestQuality
        }
    }
    
    private func createVideoComposition(for videoTrack: AVAssetTrack, quality: VideoQuality) async throws -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        
        // Get natural size
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        // Calculate output size based on quality
        let targetSize = quality.resolution
        let videoSize = naturalSize.applying(preferredTransform)
        
        // Create layer instructions
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await videoTrack.load(.timeRange).duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        // Calculate scale to fit target resolution
        let scaleX = targetSize.width / abs(videoSize.width)
        let scaleY = targetSize.height / abs(videoSize.height)
        let scale = min(scaleX, scaleY)
        
        let transform = preferredTransform.scaledBy(x: scale, y: scale)
        layerInstruction.setTransform(transform, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        
        // Set frame rate and render size
        composition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps
        composition.renderSize = targetSize
        
        // Apply bitrate through compression settings
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        
        return composition
    }
    
    /// Clean up temporary files
    func cleanupTemporaryFiles() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let documentsURL = URL(fileURLWithPath: documentsPath)
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            let compressedFiles = files.filter { $0.lastPathComponent.hasPrefix("compressed_") }
            
            for file in compressedFiles {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            print("Error cleaning up temporary files: \(error)")
        }
    }
}

// MARK: - Video Compression Errors
enum VideoCompressionError: LocalizedError {
    case durationExceeded(duration: TimeInterval)
    case noVideoTrack
    case exportSessionCreationFailed
    case cancelled
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .durationExceeded(let duration):
            return "Video duration (\(Int(duration))s) exceeds maximum allowed (30s)"
        case .noVideoTrack:
            return "No video track found in the file"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .cancelled:
            return "Compression was cancelled"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}