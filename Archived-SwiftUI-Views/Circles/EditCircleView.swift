import SwiftUI

struct EditCircleView: View {
    let circle: Circle
    let onUpdate: (Circle) -> Void
    
    @EnvironmentObject var circleManager: CircleManager
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var description: String
    @State private var selectedCategory: CircleCategory
    @State private var selectedPrivacy: PrivacyLevel
    @State private var selectedImage: UIImage?
    @State private var currentImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingImageOptions = false
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let categories: [(CircleCategory, String, String)] = [
        (.travel, "Travel", "airplane.departure"),
        (.food, "Food & Dining", "fork.knife.circle.fill"),
        (.services, "Services", "wrench.and.screwdriver.fill"),
        (.shopping, "Shopping", "bag.fill"),
        (.healthcare, "Healthcare", "heart.text.square.fill"),
        (.entertainment, "Entertainment", "music.note.tv.fill"),
        (.other, "Other", "square.stack.3d.up.fill")
    ]
    
    private let privacyOptions: [(PrivacyLevel, String, String, String)] = [
        (.public, "Public", "globe", "Anyone can see this circle"),
        (.friends, "Friends", "person.2", "Only friends can see this circle"),
        (.private, "Private", "lock", "Only you can see this circle")
    ]
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    init(circle: Circle, onUpdate: @escaping (Circle) -> Void) {
        self.circle = circle
        self.onUpdate = onUpdate
        self._name = State(initialValue: circle.name)
        self._description = State(initialValue: circle.description ?? "")
        self._selectedCategory = State(initialValue: circle.category)
        self._selectedPrivacy = State(initialValue: circle.privacy)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Cover Image Section
                Section {
                    VStack {
                        if let image = selectedImage ?? currentImage {
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
            .navigationTitle("Edit Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        updateCircle()
                    }
                    .disabled(name.isEmpty || isLoading || !hasChanges)
                }
            }
        }
        .onAppear {
            loadCurrentImage()
        }
        .confirmationDialog("Choose Image Source", isPresented: $showingImageOptions) {
            Button("Take Photo") {
                // TODO: Implement camera
            }
            Button("Choose from Library") {
                showingImagePicker = true
            }
            if selectedImage != nil || currentImage != nil {
                Button("Remove Image", role: .destructive) {
                    selectedImage = nil
                    currentImage = nil
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
                    ProgressView("Updating Circle...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        )
    }
    
    private var hasChanges: Bool {
        name != circle.name ||
        description != (circle.description ?? "") ||
        selectedCategory != circle.category ||
        selectedPrivacy != circle.privacy ||
        selectedImage != nil
    }
    
    private func loadCurrentImage() {
        guard let urlString = circle.coverImage,
              let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.currentImage = image
                }
            }
        }.resume()
    }
    
    private func updateCircle() {
        guard !name.isEmpty else { return }
        
        isLoading = true
        
        Task {
            do {
                try await circleManager.updateCircle(
                    circle,
                    name: name,
                    description: description.isEmpty ? nil : description,
                    category: selectedCategory.rawValue,
                    privacy: selectedPrivacy.rawValue,
                    coverImage: selectedImage
                )
                
                await MainActor.run {
                    // The circle will be updated by CircleManager
                    // Just dismiss the view
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

#Preview {
    EditCircleView(
        circle: Circle(
            id: "1",
            name: "Test Circle",
            description: "Test Description",
            coverImage: nil,
            owner: "user1",
            ownerDetails: nil,
            places: [],
            placesWithDetails: nil,
            privacy: .friends,
            category: .food,
            location: nil,
            tags: nil,
            sharedWith: nil,
            followers: nil,
            activeShares: nil,
            shareSettings: nil,
            isSharedWithMe: false,
            sharedBy: nil,
            myAccessLevel: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onUpdate: { _ in }
    )
    .environmentObject(CircleManager.shared)
}