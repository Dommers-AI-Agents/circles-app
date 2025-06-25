import SwiftUI
import GoogleMaps
import UIKit
import MapKit

struct PlaceDetailView: View {
    let place: Place
    @Environment(\.dismiss) var dismiss
    @State private var mapCenter: CLLocationCoordinate2D
    @State private var mapZoom: Float = 16.0
    @State private var showingShareSheet = false
    @State private var placePhotos: [UIImage] = []
    @State private var isLoadingPhotos = false
    @State private var googlePlaceDetails: GooglePlaceDetails?
    @State private var selectedPhotoIndex = 0
    @State private var streetViewImage: UIImage?
    @State private var showingStreetView = false
    @State private var isStreetViewAvailable = false
    @State private var showingEditPlace = false
    @State private var showingDeleteAlert = false
    @State private var showingEditNotes = false
    @State private var editingPrivateNotes = ""
    @State private var editingPublicNotes = ""
    @EnvironmentObject var placeManager: PlaceManager
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    init(place: Place) {
        self.place = place
        let coordinate = place.location?.clLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        self._mapCenter = State(initialValue: coordinate)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Photos
                photoSection
                
                // Basic Info
                basicInfoSection
                    .padding(.horizontal)
                
                // Contact Info
                contactSection
                    .padding(.horizontal)
                
                // Description & Notes
                descriptionSection
                    .padding(.horizontal)
                
                // Opening Hours
                if let hours = place.openingHours, !hours.isEmpty {
                    openingHoursSection(hours: hours)
                        .padding(.horizontal)
                }
                
                // Reviews
                if let reviews = place.reviews, !reviews.isEmpty {
                    reviewsSection(reviews: reviews)
                        .padding(.horizontal)
                }
                
                // Actions
                actionButtons
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
        .navigationTitle("Place Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingShareSheet = true }) {
                        Label("Share Place", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: { showingEditPlace = true }) {
                        Label("Edit Place", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive, action: { showingDeleteAlert = true }) {
                        Label("Delete Place", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: placeManager.sharePlace(place))
        }
        .sheet(isPresented: $showingEditPlace) {
            EditPlaceView(
                place: place,
                onUpdate: { updatedPlace in
                    // The place will be updated in the backend
                    // You might want to refresh the parent view
                }
            )
            .environmentObject(placeManager)
        }
        .sheet(isPresented: $showingEditNotes) {
            EditNotesView(
                place: place,
                privateNotes: $editingPrivateNotes,
                publicNotes: $editingPublicNotes,
                onSave: saveNotes
            )
        }
        .alert("Delete Place", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePlace()
            }
        } message: {
            Text("Are you sure you want to delete this place? This action cannot be undone.")
        }
        .onAppear {
            loadPlacePhotos()
            loadGooglePlaceDetails()
            checkStreetViewAvailability()
        }
    }
    
    @ViewBuilder
    private var photoSection: some View {
        ZStack(alignment: .topTrailing) {
            if showingStreetView, let streetViewImage = streetViewImage {
                Image(uiImage: streetViewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 300)
                    .clipped()
            } else if !placePhotos.isEmpty {
                TabView(selection: $selectedPhotoIndex) {
                    ForEach(Array(placePhotos.enumerated()), id: \.offset) { index, photo in
                        Image(uiImage: photo)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 300)
                            .clipped()
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle())
                .frame(height: 300)
            } else if place.location != nil {
                GoogleMapViewWrapper(
                    center: $mapCenter,
                    markers: [GoogleMapMarker(place: place)],
                    zoom: mapZoom,
                    showsUserLocation: false
                )
                .frame(height: 300)
            }
            
            // Street View Toggle Button
            if isStreetViewAvailable && place.location != nil {
                Button(action: {
                    withAnimation {
                        showingStreetView.toggle()
                        if showingStreetView && streetViewImage == nil {
                            loadStreetViewImage()
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showingStreetView ? "photo" : "person.and.arrow.left.and.arrow.right")
                            .font(.caption)
                        Text(showingStreetView ? "Photos" : "Street View")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
                .padding(12)
            }
        }
    }
    
    @ViewBuilder
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name and Share Button
            HStack(alignment: .top) {
                Text(place.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 16)
                
                Button(action: { showingShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(circlesBlue)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(SwiftUI.Circle())
                }
            }
            
            HStack(spacing: 20) {
                // Rating
                if let rating = place.rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(String(format: "%.1f", rating))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let total = place.userRatingsTotal {
                            Text("(\(total))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Price Level
                if let priceLevel = place.priceLevel {
                    Text(priceLevel.displaySymbol)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                
                Spacer()
            }
            
            // Category
            HStack {
                Image(systemName: place.category.systemIconName)
                    .foregroundColor(.gray)
                Text(place.category.displayName)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }
    
    @ViewBuilder
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !place.address.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "mappin.circle")
                        .foregroundColor(.gray)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.address)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        if place.location != nil {
                            Button(action: openInMaps) {
                                HStack(spacing: 4) {
                                    Image(systemName: "location.fill")
                                        .font(.caption)
                                    Text("Get Directions")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(circlesBlue)
                            }
                        }
                    }
                    Spacer()
                }
            }
            
            if let website = place.website, !website.isEmpty {
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.gray)
                    Link(website, destination: URL(string: website) ?? URL(string: "https://")!)
                        .font(.subheadline)
                }
            }
            
            if let phone = place.phone, !phone.isEmpty {
                HStack {
                    Image(systemName: "phone")
                        .foregroundColor(.gray)
                    Link(phone, destination: URL(string: "tel:\(phone)") ?? URL(string: "tel:")!)
                        .font(.subheadline)
                }
            }
        }
    }
    
    @ViewBuilder
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let description = place.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.headline)
                    Text(description)
                        .font(.body)
                }
            }
            
            // Notes Section Header with Edit Button
            if place.isAddedByCurrentUser {
                HStack {
                    Text("Notes")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        editingPrivateNotes = place.privateNotes ?? ""
                        editingPublicNotes = place.publicNotes ?? place.notes ?? ""
                        showingEditNotes = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.caption)
                            Text("Edit")
                                .font(.caption)
                        }
                        .foregroundColor(circlesBlue)
                    }
                }
            }
            
            // Public Notes (visible to everyone)
            if let publicNotes = place.publicNotes ?? place.notes, !publicNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Public Notes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(publicNotes)
                        .font(.body)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            // Private Notes (only visible to the user who added them)
            if place.isAddedByCurrentUser {
                if let privateNotes = place.privateNotes, !privateNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Private Notes")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(privateNotes)
                            .font(.body)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                } else if place.publicNotes == nil || place.publicNotes?.isEmpty == true {
                    // Show prompt to add notes if both are empty
                    Button(action: {
                        editingPrivateNotes = ""
                        editingPublicNotes = ""
                        showingEditNotes = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Add Notes")
                        }
                        .foregroundColor(circlesBlue)
                        .font(.subheadline)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    @ViewBuilder
    private func openingHoursSection(hours: [OpeningHour]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hours")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(hours.indices, id: \.self) { index in
                    let hour = hours[index]
                    HStack {
                        Text(dayName(for: hour.day))
                            .font(.subheadline)
                            .frame(width: 80, alignment: .leading)
                        
                        if hour.isClosed {
                            Text("Closed")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        } else {
                            Text("\(hour.open) - \(hour.close)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private func reviewsSection(reviews: [PlaceReview]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reviews")
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(reviews.prefix(5)) { review in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(review.user)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                HStack(spacing: 4) {
                                    ForEach(1...5, id: \.self) { index in
                                        Image(systemName: index <= Int(review.rating) ? "star.fill" : "star")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(review.date, style: .relative)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        
                        if let comment = review.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(4)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(10)
                }
            }
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Get Directions Button
            if place.location != nil {
                Button(action: openInMaps) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Get Directions")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(circlesBlue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
    }
    
    private func dayName(for day: Int) -> String {
        switch day {
        case 0: return "Sunday"
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
        default: return "Unknown"
        }
    }
    
    private func shareContent() -> String {
        // Use PlaceManager's sharePlace method for consistent formatting
        let shareItems = placeManager.sharePlace(place)
        if let shareText = shareItems.first as? String {
            return shareText
        }
        // Fallback to basic format
        return "Check out \(place.name)!"
    }
    
    private func loadPlacePhotos() {
        guard let googlePlaceId = place.googlePlaceId, !googlePlaceId.isEmpty else { return }
        
        isLoadingPhotos = true
        GooglePlacesService.shared.fetchPlaceDetails(placeID: googlePlaceId) { result in
            switch result {
            case .success(let gmsPlace):
                let googleDetails = GooglePlaceDetails(from: gmsPlace)
                let photosToLoad = Array(googleDetails.photos.prefix(3))
                
                guard !photosToLoad.isEmpty else {
                    DispatchQueue.main.async {
                        self.isLoadingPhotos = false
                    }
                    return
                }
                
                var loadedCount = 0
                for metadata in photosToLoad {
                    GooglePlacesService.shared.loadPhoto(from: metadata) { photoResult in
                        switch photoResult {
                        case .success(let image):
                            DispatchQueue.main.async {
                                self.placePhotos.append(image)
                                loadedCount += 1
                                if loadedCount == photosToLoad.count {
                                    self.isLoadingPhotos = false
                                }
                            }
                        case .failure:
                            loadedCount += 1
                            if loadedCount == photosToLoad.count {
                                DispatchQueue.main.async {
                                    self.isLoadingPhotos = false
                                }
                            }
                        }
                    }
                }
                
            case .failure:
                DispatchQueue.main.async {
                    self.isLoadingPhotos = false
                }
            }
        }
    }
    
    private func loadGooglePlaceDetails() {
        guard let googlePlaceId = place.googlePlaceId, !googlePlaceId.isEmpty else { return }
        
        GooglePlacesService.shared.fetchPlaceDetails(placeID: googlePlaceId) { result in
            switch result {
            case .success(let gmsPlace):
                let details = GooglePlaceDetails(from: gmsPlace)
                DispatchQueue.main.async {
                    self.googlePlaceDetails = details
                }
            case .failure(let error):
                print("Failed to load Google Place details: \(error)")
            }
        }
    }
    
    private func openInMaps() {
        guard let location = place.location?.clLocation else { return }
        
        // Create the Apple Maps URL with destination
        let coordinate = location.coordinate
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = place.name
        
        // Open in Apple Maps with directions
        let launchOptions = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ]
        
        mapItem.openInMaps(launchOptions: launchOptions)
    }
    
    private func checkStreetViewAvailability() {
        guard let location = place.location?.clLocation else { return }
        
        GoogleStreetViewService.shared.checkStreetViewAvailability(at: location.coordinate) { available in
            DispatchQueue.main.async {
                self.isStreetViewAvailable = available
            }
        }
    }
    
    private func loadStreetViewImage() {
        guard let location = place.location?.clLocation else { return }
        
        let screenSize = UIScreen.main.bounds.size
        let imageSize = CGSize(width: screenSize.width, height: 300)
        
        let parameters = GoogleStreetViewService.StreetViewParameters(
            location: location.coordinate,
            size: imageSize
        )
        
        GoogleStreetViewService.shared.downloadStreetViewImage(parameters: parameters) { imageData in
            guard let data = imageData, let image = UIImage(data: data) else { return }
            
            DispatchQueue.main.async {
                self.streetViewImage = image
            }
        }
    }
    
    private func deletePlace() {
        Task {
            do {
                try await placeManager.deletePlace(place)
                // Dismiss the view after successful deletion
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("Failed to delete place: \(error)")
            }
        }
    }
    
    private func saveNotes() {
        Task {
            do {
                // Update the place with new notes
                let updatedPlace = try await placeManager.updatePlaceNotes(
                    place,
                    privateNotes: editingPrivateNotes.isEmpty ? nil : editingPrivateNotes,
                    publicNotes: editingPublicNotes.isEmpty ? nil : editingPublicNotes
                )
                
                // Dismiss the edit sheet
                await MainActor.run {
                    showingEditNotes = false
                }
            } catch {
                print("Failed to update notes: \(error)")
            }
        }
    }
}


