import SwiftUI
import MapKit
import PhotosUI

struct EditPlaceView: View {
    let place: Place
    let onUpdate: (Place) -> Void
    
    @EnvironmentObject var placeManager: PlaceManager
    @Environment(\.dismiss) var dismiss
    
    // Editable fields
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var privateNotes: String = ""
    @State private var publicNotes: String = ""
    @State private var selectedCategory: String = ""
    @State private var selectedPrivacy: String = ""
    @State private var website: String = ""
    @State private var phone: String = ""
    @State private var tags: String = ""
    
    // UI State
    @State private var isUpdating = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingDeleteAlert = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var newPhotoData: [Data] = []
    @State private var photosToRemove: [String] = []
    
    private let privacyOptions = [
        ("followCircle", "Follow Circle Privacy", "circle", "Use the same privacy setting as the circle"),
        ("public", "Public", "globe", "Anyone can see this place"),
        ("friends", "Friends Only", "person.2", "Only friends can see this place"),
        ("private", "Private", "lock", "Only you can see this place")
    ]
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        NavigationView {
            Form {
                basicInformationSection
                contactInformationSection
                notesSection
                tagsSection
                photosSection
                privacySection
                deleteSection
            }
            .navigationTitle("Edit Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        updatePlace()
                    }
                    .disabled(isUpdating || name.isEmpty || address.isEmpty)
                }
            }
        }
        .onAppear {
            loadPlaceData()
        }
        .onChange(of: selectedPhotos) { newValue in
            Task {
                newPhotoData.removeAll()
                for item in newValue {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        newPhotoData.append(data)
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Delete Place", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePlace()
            }
        } message: {
            Text("Are you sure you want to delete this place? This action cannot be undone.")
        }
        .overlay(
            Group {
                if isUpdating {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView("Updating Place...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        )
    }
    
    @ViewBuilder
    private var basicInformationSection: some View {
        Section(header: Text("Basic Information")) {
                    TextField("Name", text: $name)
                    
                    TextField("Address", text: $address)
                    
                    HStack {
                        Text("Category")
                        Spacer()
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(PlaceCategory.allCases, id: \.rawValue) { category in
                                Text(category.displayName).tag(category.rawValue)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
        }
    }
    
    @ViewBuilder
    private var contactInformationSection: some View {
        Section(header: Text("Contact Information")) {
                    TextField("Website", text: $website)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
        }
    }
    
    @ViewBuilder
    private var notesSection: some View {
        Section(header: Text("Notes")) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Private Notes", systemImage: "lock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: $privateNotes)
                                .frame(minHeight: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Public Notes", systemImage: "globe")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: $publicNotes)
                                .frame(minHeight: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
        }
    }
    
    @ViewBuilder
    private var tagsSection: some View {
        Section(header: Text("Tags"), footer: Text("Separate tags with commas")) {
                    TextField("e.g. vegan, outdoor seating, wifi", text: $tags)
        }
    }
    
    @ViewBuilder
    private var photosSection: some View {
        Section(header: Text("Photos")) {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                            .foregroundColor(circlesBlue)
                    }
                    
                    if !newPhotoData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(newPhotoData.indices, id: \.self) { index in
                                    if let uiImage = UIImage(data: newPhotoData[index]) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 100, height: 100)
                                            .cornerRadius(8)
                                            .overlay(
                                                Button(action: {
                                                    newPhotoData.remove(at: index)
                                                    selectedPhotos.remove(at: index)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.red)
                                                        .background(Color.white.clipShape(SwiftUI.Circle()))
                                                }
                                                .padding(4),
                                                alignment: .topTrailing
                                            )
                                    }
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                    
                    // Existing photos
                    if let photos = place.photos, !photos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Photos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(photos, id: \.self) { photoUrl in
                                        AsyncImage(url: URL(string: photoUrl)) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            ProgressView()
                                        }
                                        .frame(width: 100, height: 100)
                                        .cornerRadius(8)
                                        .opacity(photosToRemove.contains(photoUrl) ? 0.5 : 1.0)
                                        .overlay(
                                            Button(action: {
                                                if photosToRemove.contains(photoUrl) {
                                                    photosToRemove.removeAll { $0 == photoUrl }
                                                } else {
                                                    photosToRemove.append(photoUrl)
                                                }
                                            }) {
                                                Image(systemName: photosToRemove.contains(photoUrl) ? "arrow.uturn.backward.circle.fill" : "trash.circle.fill")
                                                    .foregroundColor(photosToRemove.contains(photoUrl) ? .green : .red)
                                                    .background(Color.white.clipShape(SwiftUI.Circle()))
                                            }
                                            .padding(4),
                                            alignment: .topTrailing
                                        )
                                    }
                                }
                            }
                        }
                    }
        }
    }
    
    @ViewBuilder
    private var privacySection: some View {
        Section(header: Text("Privacy Settings")) {
                    ForEach(privacyOptions, id: \.0) { option in
                        HStack {
                            Image(systemName: option.2)
                                .frame(width: 30)
                                .foregroundColor(circlesBlue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.1)
                                    .font(.body)
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPrivacy = option.0
                        }
                    }
        }
    }
    
    @ViewBuilder
    private var deleteSection: some View {
        Section {
                    Button(action: { showingDeleteAlert = true }) {
                        Label("Delete Place", systemImage: "trash")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                    }
        }
    }
    
    private func loadPlaceData() {
        name = place.name
        address = place.address ?? ""
        privateNotes = place.privateNotes ?? ""
        publicNotes = place.publicNotes ?? place.notes ?? ""
        selectedCategory = place.category.rawValue
        selectedPrivacy = place.privacy.rawValue
        website = place.website ?? ""
        phone = place.phone ?? ""
        tags = place.tags?.joined(separator: ", ") ?? ""
    }
    
    private func updatePlace() {
        isUpdating = true
        
        Task {
            do {
                // Prepare the update data
                let tagsArray = tags.isEmpty ? nil : tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                
                // Call the comprehensive update method
                let updatedPlace = try await placeManager.updatePlaceComprehensive(
                    place,
                    name: name,
                    address: address,
                    category: PlaceCategory(rawValue: selectedCategory) ?? .other,
                    privacy: PlacePrivacy(rawValue: selectedPrivacy) ?? .followCirclePrivacy,
                    website: website.isEmpty ? nil : website,
                    phone: phone.isEmpty ? nil : phone,
                    tags: tagsArray,
                    privateNotes: privateNotes.isEmpty ? nil : privateNotes,
                    publicNotes: publicNotes.isEmpty ? nil : publicNotes,
                    addPhotos: newPhotoData.isEmpty ? nil : newPhotoData,
                    removePhotoUrls: photosToRemove.isEmpty ? nil : photosToRemove
                )
                
                await MainActor.run {
                    onUpdate(updatedPlace)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isUpdating = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func deletePlace() {
        Task {
            do {
                try await placeManager.deletePlace(place)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

#Preview {
    EditPlaceView(
        place: Place(
            id: "1",
            name: "Test Place",
            description: nil,
            address: "123 Main St",
            location: nil,
            website: "https://example.com",
            phone: "555-1234",
            googlePlaceId: nil,
            photos: [],
            category: .restaurant,
            rating: 4.5,
            userRatingsTotal: 100,
            notes: "Great place",
            privateNotes: "My favorite",
            publicNotes: "Must try the pizza",
            tags: ["italian", "pizza"],
            reviews: nil,
            openingHours: nil,
            priceLevel: .moderate,
            circleId: "circle1",
            addedBy: "user1",
            addedByUser: nil,
            privacy: .friends,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onUpdate: { _ in }
    )
    .environmentObject(PlaceManager.shared)
}