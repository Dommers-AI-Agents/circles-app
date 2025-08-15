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
                
                print("📹 Export session configuration:")
                print("  - Preset: \(getPresetName(for: quality))")
                print("  - Output URL: \(outputURL.lastPathComponent)")
                
                // Set time range to trim video to 15 seconds if needed
                if durationInSeconds > maxDuration {
                    let startTime = CMTime.zero
                    let endTime = CMTime(seconds: maxDuration, preferredTimescale: duration.timescale)
                    exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)
                    print("📹 Auto-trimming video from \(durationInSeconds)s to \(maxDuration)s")
                }
                
                // Check if this is a camera-recorded video by examining the transform
                // Camera videos often have specific transform values
                let preferredTransform = try await videoTrack.load(.preferredTransform)
                let naturalSize = try await videoTrack.load(.naturalSize)
                
                // Detect if this is likely a camera-recorded portrait video
                // These often have issues with custom video compositions
                let isCameraPortraitVideo = (preferredTransform.a == 0 && abs(preferredTransform.b) == 1) ||
                                           (abs(preferredTransform.a) == 1 && preferredTransform.b == 0 && naturalSize.width > naturalSize.height)
                
                if isCameraPortraitVideo {
                    // For camera-recorded videos, skip custom composition
                    // Let the export preset handle orientation naturally
                    print("📹 Camera video detected - using native export without custom composition")
                    print("  - Transform: a=\(preferredTransform.a), b=\(preferredTransform.b)")
                    print("  - Natural size: \(naturalSize)")
                    // Don't set videoComposition - let export preset handle it
                } else {
                    // For other videos (library uploads, etc), apply custom composition
                    print("📹 Non-camera video - applying custom composition")
                    let videoComposition = try await createVideoComposition(for: videoTrack, quality: quality)
                    exportSession.videoComposition = videoComposition
                }
                
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
        // Use presets that properly handle video orientation
        switch quality {
        case .preview:
            // Use medium quality which handles orientation well
            // and produces reasonable file sizes
            return AVAssetExportPresetMediumQuality
        case .full:
            // Use high quality for full resolution
            return AVAssetExportPresetHighestQuality
        }
    }
    
    private func createVideoComposition(for videoTrack: AVAssetTrack, quality: VideoQuality) async throws -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        
        // Get natural size and transform
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        // Apply transform to get actual video dimensions
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let videoSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        
        // Determine video orientation based on actual dimensions after transform
        let orientation = VideoOrientation.from(size: videoSize)
        
        // Get appropriate target size based on orientation
        let targetSize = quality.resolution(for: orientation)
        
        // Enhanced debug logging
        print("📹 Video compression debug:")
        print("  - Natural size: \(naturalSize)")
        print("  - Preferred transform: \(preferredTransform)")
        print("  - Transformed size: \(videoSize)")
        print("  - Detected orientation: \(orientation)")
        print("  - Target resolution: \(targetSize)")
        print("  - Quality preset: \(quality)")
        
        // Create layer instructions
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await videoTrack.load(.timeRange).duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        // For portrait videos from iPhone, we need to handle the rotation properly
        if orientation == .portrait {
            // iPhone portrait videos typically have a 90 degree rotation
            // Natural size is landscape but needs to be displayed as portrait
            
            print("📹 Processing portrait video transform:")
            print("  - Natural size (pre-rotation): \(naturalSize)")
            print("  - Video size (post-rotation): \(videoSize)")
            print("  - Target size: \(targetSize)")
            print("  - Preferred transform: a=\(preferredTransform.a), b=\(preferredTransform.b), c=\(preferredTransform.c), d=\(preferredTransform.d), tx=\(preferredTransform.tx), ty=\(preferredTransform.ty)")
            
            // Simplified approach: Let the export session handle most of the transform
            // Just apply the preferred transform and scale to fit the target
            var transform = CGAffineTransform.identity
            
            // Apply the video's preferred transform (handles rotation)
            transform = transform.concatenating(preferredTransform)
            
            // Now scale to fill the target size
            // After rotation, the video is in portrait orientation
            let scaleX = targetSize.width / videoSize.width
            let scaleY = targetSize.height / videoSize.height
            let scale = max(scaleX, scaleY) // Aspect fill
            
            print("  - Scale: \(scale)")
            
            // Apply scale
            transform = transform.scaledBy(x: scale, y: scale)
            
            // Calculate where the video ends up after transform
            let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
            
            // Center it in the target frame
            let translateX = (targetSize.width - transformedRect.width) / 2 - transformedRect.minX
            let translateY = (targetSize.height - transformedRect.height) / 2 - transformedRect.minY
            
            print("  - Transformed rect: \(transformedRect)")
            print("  - Translation: X=\(translateX), Y=\(translateY)")
            
            transform = transform.translatedBy(x: translateX, y: translateY)
            
            layerInstruction.setTransform(transform, at: .zero)
            
        } else {
            // For landscape or square videos, also use aspect fill for consistency
            let scaleX = targetSize.width / naturalSize.width
            let scaleY = targetSize.height / naturalSize.height
            let scale = max(scaleX, scaleY) // Use max for aspect fill
            
            var transform = preferredTransform.scaledBy(x: scale, y: scale)
            
            // Center the video (it will be cropped if needed)
            let scaledSize = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
            let xOffset = (targetSize.width - scaledSize.width) / 2
            let yOffset = (targetSize.height - scaledSize.height) / 2
            
            transform = transform.translatedBy(x: xOffset, y: yOffset)
            layerInstruction.setTransform(transform, at: .zero)
        }
        
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        
        // Set frame rate and render size
        composition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps
        composition.renderSize = targetSize
        
        // IMPORTANT: Set render scale to 1.0 to avoid scaling issues
        composition.renderScale = 1.0
        
        // Apply compression settings
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        
        print("📹 Video composition final settings:")
        print("  - Render size: \(composition.renderSize)")
        print("  - Frame duration: \(composition.frameDuration.seconds)s")
        print("  - Instructions count: \(composition.instructions.count)")
        
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