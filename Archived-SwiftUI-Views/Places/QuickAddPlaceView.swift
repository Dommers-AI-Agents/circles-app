import SwiftUI
import GooglePlaces
import CoreLocation

struct QuickAddPlaceView: View {
    let circle: Circle
    let placeID: String
    let placeName: String
    let location: CLLocationCoordinate2D
    let onPlaceAdded: (Place) -> Void
    let onCancel: () -> Void
    
    @EnvironmentObject var placeManager: PlaceManager
    @Environment(\.dismiss) var dismiss
    
    @State private var placeDetails: GooglePlaceDetails?
    @State private var notes = ""
    @State private var privateNotes = ""
    @State private var publicNotes = ""
    @State private var selectedCategory: String?
    @State private var selectedPrivacy = "followCircle"
    @State private var isLoading = true
    @State private var isAddingPlace = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let privacyOptions = [
        ("followCircle", "Follow Circle Privacy", "circle", "Use the same privacy setting as the circle"),
        ("public", "Public", "globe", "Anyone can see this place"),
        ("friends", "Friends Only", "person.2", "Only friends can see this place"),
        ("private", "Private", "lock", "Only you can see this place")
    ]
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        NavigationView {
            if isLoading {
                ProgressView("Loading place details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Add Place")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                onCancel()
                                dismiss()
                            }
                        }
                    }
            } else if let details = placeDetails {
                Form {
                    // Place info section
                    Section(header: Text("Place Information")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(details.name)
                                .font(.headline)
                            
                            if let address = details.address {
                                Text(address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Category section
                    Section(header: Text("Category")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(PlaceCategory.allCases, id: \.self) { category in
                                    PlaceCategoryButton(
                                        title: category.displayName,
                                        isSelected: selectedCategory == category.rawValue
                                    ) {
                                        selectedCategory = category.rawValue
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // Notes section
                    Section(header: Text("Notes")) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Private Notes", systemImage: "lock")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextEditor(text: $privateNotes)
                                    .frame(minHeight: 60)
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
                                    .frame(minHeight: 60)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    
                    // Privacy section
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
                .navigationTitle("Add Place")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Add") {
                            addPlace()
                        }
                        .disabled(isAddingPlace)
                    }
                }
            }
        }
        .onAppear {
            fetchPlaceDetails()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .overlay(
            Group {
                if isAddingPlace {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView("Adding Place...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        )
    }
    
    private func fetchPlaceDetails() {
        GooglePlacesService.shared.fetchPlaceDetails(placeID: placeID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let place):
                    self.placeDetails = GooglePlaceDetails(from: place)
                    // Auto-select category based on Google types
                    if let types = self.placeDetails?.types {
                        self.selectedCategory = self.determinePlaceCategory(from: types).rawValue
                    }
                    self.isLoading = false
                    
                case .failure(let error):
                    // If we can't get details, create a basic place with the info we have
                    self.placeDetails = GooglePlaceDetails(
                        placeID: placeID,
                        name: placeName,
                        address: nil,
                        coordinate: location,
                        phoneNumber: nil,
                        website: nil,
                        rating: nil,
                        userRatingsTotal: 0,
                        priceLevel: nil,
                        types: [],
                        photos: [],
                        openingHours: nil,
                        isOpen: nil
                    )
                    self.isLoading = false
                    print("Failed to fetch place details: \(error)")
                }
            }
        }
    }
    
    private func determinePlaceCategory(from types: [String]) -> PlaceCategory {
        if types.contains(where: { $0.contains("restaurant") || $0.contains("food") }) {
            return .restaurant
        } else if types.contains(where: { $0.contains("cafe") || $0.contains("coffee") }) {
            return .cafe
        } else if types.contains(where: { $0.contains("bar") || $0.contains("nightlife") }) {
            return .bar
        } else if types.contains(where: { $0.contains("shopping") || $0.contains("store") }) {
            return .retail
        } else if types.contains(where: { $0.contains("lodging") || $0.contains("hotel") }) {
            return .hotel
        } else if types.contains(where: { $0.contains("park") || $0.contains("outdoor") }) {
            return .outdoor
        } else if types.contains(where: { $0.contains("attraction") || $0.contains("museum") }) {
            return .attraction
        } else {
            return .other
        }
    }
    
    private func addPlace() {
        guard let details = placeDetails else { return }
        
        isAddingPlace = true
        
        Task {
            do {
                var placeData: [String: Any] = [
                    "name": details.name,
                    "address": details.address ?? "",
                    "location": [
                        "type": "Point",
                        "coordinates": [details.coordinate.longitude, details.coordinate.latitude]
                    ],
                    "googlePlaceId": details.placeID,
                    "category": selectedCategory ?? "other",
                    "circleId": circle.id,
                    "privacy": selectedPrivacy
                ]
                
                // Add optional fields
                if let website = details.website {
                    placeData["website"] = website.absoluteString
                }
                if let phone = details.phoneNumber {
                    placeData["phone"] = phone
                }
                if let rating = details.rating {
                    placeData["rating"] = rating
                    placeData["userRatingsTotal"] = details.userRatingsTotal
                }
                if let priceLevel = details.priceLevel {
                    placeData["priceLevel"] = priceLevel.rawValue
                }
                if !details.types.isEmpty {
                    placeData["tags"] = details.types
                }
                
                // Add notes
                if !privateNotes.isEmpty {
                    placeData["privateNotes"] = privateNotes
                }
                if !publicNotes.isEmpty {
                    placeData["publicNotes"] = publicNotes
                }
                
                let newPlace = try await placeManager.createPlaceWithGoogleData(placeData)
                
                await MainActor.run {
                    onPlaceAdded(newPlace)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAddingPlace = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

private struct PlaceCategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? circlesBlue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(15)
        }
    }
}