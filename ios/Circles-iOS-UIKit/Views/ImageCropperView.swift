import SwiftUI
import UIKit

struct ImageCropperView: UIViewControllerRepresentable {
    let image: UIImage
    let onCrop: (UIImage?) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> ImageCropperViewController {
        let cropperVC = ImageCropperViewController(image: image)
        cropperVC.delegate = context.coordinator
        return cropperVC
    }
    
    func updateUIViewController(_ uiViewController: ImageCropperViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCrop: onCrop, onCancel: onCancel)
    }
    
    class Coordinator: NSObject, ImageCropperDelegate {
        let onCrop: (UIImage?) -> Void
        let onCancel: () -> Void
        
        init(onCrop: @escaping (UIImage?) -> Void, onCancel: @escaping () -> Void) {
            self.onCrop = onCrop
            self.onCancel = onCancel
        }
        
        func imageCropperDidCrop(_ image: UIImage) {
            onCrop(image)
        }
        
        func imageCropperDidCancel() {
            onCancel()
        }
    }
}

// Reuse the existing ImageCropperViewController from UIKit
extension View {
    func imageCropper(
        isPresented: Binding<Bool>,
        image: UIImage?,
        onCrop: @escaping (UIImage?) -> Void
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            if let image = image {
                ImageCropperView(
                    image: image,
                    onCrop: { croppedImage in
                        onCrop(croppedImage)
                        isPresented.wrappedValue = false
                    },
                    onCancel: {
                        isPresented.wrappedValue = false
                    }
                )
            }
        }
    }
}