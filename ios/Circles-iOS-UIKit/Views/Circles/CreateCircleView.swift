import SwiftUI
import PhotosUI

struct CreateCircleView: View {
    @EnvironmentObject var circleManager: CircleManager
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var selectedCategory = "other"
    @State private var selectedPrivacy = "friends"
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingImageOptions = false
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let categories = [
        ("travel", "Travel", "airplane"),
        ("food", "Food & Dining", "fork.knife"),
        ("services", "Services", "wrench.and.screwdriver"),
        ("shopping", "Shopping", "bag"),
        ("healthcare", "Healthcare", "heart"),
        ("entertainment", "Entertainment", "tv"),
        ("other", "Other", "circle.grid.3x3")
    ]
    
    private let privacyOptions = [
        ("public", "Public", "globe", "Anyone can see this circle"),
        ("friends", "Friends", "person.2", "Only friends can see this circle"),
        ("private", "Private", "lock", "Only you can see this circle")
    ]
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        NavigationView {
            Form {
                // Cover Image Section
                Section {
                    VStack {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 200)
                                .clipped()
                                .cornerRadius(10)
                                .onTapGesture {
                                    showingImageOptions = true
                                }
                        } else {
                            Button(action: { showingImageOptions = true }) {
                                VStack(spacing: 10) {
                                    Image(systemName: "camera.fill")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    Text("Add Cover Image")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                
                // Basic Info Section
                Section(header: Text("Basic Information")) {
                    TextField("Circle Name", text: $name)
                    
                    VStack(alignment: .leading) {
                        Text("Description (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $description)
                            .frame(minHeight: 80)
                    }
                }
                
                // Category Section
                Section(header: Text("Category")) {
                    ForEach(categories, id: \.0) { category in
                        HStack {
                            Image(systemName: category.2)
                                .foregroundColor(selectedCategory == category.0 ? circlesBlue : .secondary)
                                .frame(width: 30)
                            
                            Text(category.1)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedCategory == category.0 {
                                Image(systemName: "checkmark")
                                    .foregroundColor(circlesBlue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCategory = category.0
                        }
                    }
                }
                
                // Privacy Section
                Section(header: Text("Privacy")) {
                    ForEach(privacyOptions, id: \.0) { option in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: option.2)
                                    .foregroundColor(selectedPrivacy == option.0 ? circlesBlue : .secondary)
                                    .frame(width: 30)
                                
                                VStack(alignment: .leading) {
                                    Text(option.1)
                                        .foregroundColor(.primary)
                                    Text(option.3)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedPrivacy == option.0 {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(circlesBlue)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPrivacy = option.0
                        }
                    }
                }
            }
            .navigationTitle("New Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createCircle()
                    }
                    .disabled(name.isEmpty || isLoading)
                }
            }
        }
        .confirmationDialog("Choose Image Source", isPresented: $showingImageOptions) {
            Button("Take Photo") {
                // TODO: Implement camera
            }
            Button("Choose from Library") {
                showingImagePicker = true
            }
            if selectedImage != nil {
                Button("Remove Image", role: .destructive) {
                    selectedImage = nil
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .overlay(
            Group {
                if isLoading {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView("Creating Circle...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        )
    }
    
    private func createCircle() {
        guard !name.isEmpty else { return }
        
        isLoading = true
        
        Task {
            do {
                let _ = try await circleManager.createCircle(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    category: selectedCategory,
                    privacy: selectedPrivacy,
                    coverImage: selectedImage
                )
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
}

// Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    CreateCircleView()
        .environmentObject(CircleManager.shared)
}