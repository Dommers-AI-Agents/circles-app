import UIKit

extension UIImage {
    
    /// Resize image to fit within the specified size while maintaining aspect ratio
    func resized(to targetSize: CGSize) -> UIImage {
        // Calculate the scaling factor to fit within target size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let scaleFactor = min(widthRatio, heightRatio)
        
        // Don't scale up images smaller than target
        if scaleFactor >= 1.0 {
            return self
        }
        
        // Calculate new size
        let scaledSize = CGSize(
            width: size.width * scaleFactor,
            height: size.height * scaleFactor
        )
        
        // Create renderer with new size
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        
        // Render the resized image
        let resizedImage = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: scaledSize))
        }
        
        return resizedImage
    }
    
    /// Crop image to square aspect ratio from center
    func croppedToSquare() -> UIImage {
        let size = min(self.size.width, self.size.height)
        let originX = (self.size.width - size) / 2
        let originY = (self.size.height - size) / 2
        
        let cropRect = CGRect(x: originX, y: originY, width: size, height: size)
        
        guard let cgImage = self.cgImage?.cropping(to: cropRect) else {
            return self
        }
        
        return UIImage(cgImage: cgImage, scale: self.scale, orientation: self.imageOrientation)
    }
    
    /// Compress image data with specified quality
    func compressed(quality: CGFloat = 0.7) -> Data? {
        return self.jpegData(compressionQuality: quality)
    }
    
    /// Create a thumbnail version of the image suitable for upload
    func thumbnail(maxSize: CGFloat = 400) -> UIImage {
        // First resize to thumbnail dimensions
        let thumbnailSize = CGSize(width: maxSize, height: maxSize)
        return self.resized(to: thumbnailSize)
    }
    
    /// Get optimized image data for upload (resized and compressed)
    func optimizedForUpload(maxDimension: CGFloat = 300, targetSizeKB: Int = 100) -> Data? {
        // Create smaller thumbnail for upload
        let thumbnail = self.thumbnail(maxSize: maxDimension)
        
        // Start with low quality
        var compressionQuality: CGFloat = 0.3
        var imageData = thumbnail.jpegData(compressionQuality: compressionQuality)
        
        // Target size in bytes (100KB default)
        let targetSizeBytes = targetSizeKB * 1024
        
        // Reduce quality if needed to meet target size
        while let data = imageData, 
              data.count > targetSizeBytes && 
              compressionQuality > 0.05 {
            compressionQuality -= 0.05
            imageData = thumbnail.jpegData(compressionQuality: compressionQuality)
        }
        
        // If still too large, reduce dimensions
        if let data = imageData, data.count > targetSizeBytes {
            let smallerThumbnail = self.thumbnail(maxSize: maxDimension * 0.75)
            imageData = smallerThumbnail.jpegData(compressionQuality: 0.2)
        }
        
        return imageData
    }
}