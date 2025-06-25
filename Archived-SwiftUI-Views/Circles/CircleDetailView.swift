import SwiftUI
import GoogleMaps
import CoreLocation

struct CircleDetailView: View {
    @EnvironmentObject var circleManager: CircleManager
    @EnvironmentObject var placeManager: PlaceManager
    @State private var circle: Circle
    @State private var places: [Place] = []
    @State private var isLoadingPlaces = true
    @State private var showingAddPlace = false
    @State private var showingEditCircle = false
    @State private var showingShareSheet = false
    @State private var showingDeleteAlert = false
    @State private var selectedPlace: Place?
    @State private var placeToEdit: Place?
    @State private var showingMapView = false
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
    @State private var mapZoom: Float = 12.0
    @State private var showingQuickAddPlace = false
    @State private var selectedPOI: (placeID: String, name: String, location: CLLocationCoordinate2D)?
    @State private var isUpdatingOrder = false
    @State private var orderUpdateTask: Task<Void, Never>?
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    init(circle: Circle) {
        self._circle = State(initialValue: circle)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Cover image
                CircleCoverImage(circle: circle)
                
                // Circle info
                VStack(alignment: .leading, spacing: 15) {
                    // Name and privacy
                    HStack {
                        Text(circle.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Image(systemName: privacyIcon)
                            .foregroundColor(.secondary)
                    }
                    
                    // Description
                    if let description = circle.description {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // Category and stats
                    HStack {
                        Label(circle.category.displayName, systemImage: categoryIcon)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(circlesBlue.opacity(0.1))
                            .cornerRadius(15)
                        
                        Spacer()
                        
                        Text("\(places.count) places")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                
                // Places section
                VStack(alignment: .leading, spacing: 10) {
                    // Map/List Toggle Button - ABOVE the Places header
                    HStack {
                        Spacer()
                        Button(action: { 
                            showingMapView.toggle()
                            print("🗺️ Map toggle pressed. showingMapView = \(showingMapView)")
                        }) {
                            HStack {
                                Image(systemName: showingMapView ? "list.bullet" : "map.fill")
                                    .font(.title2)
                                Text(showingMapView ? "Show List View" : "Show Map View")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(circlesBlue)
                            .cornerRadius(25)
                            .shadow(radius: 2)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    
                    // Places header
                    Text("Places")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if isLoadingPlaces {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if places.isEmpty {
                        EmptyPlacesView()
                            .padding()
                    } else {
                        if showingMapView {
                            // Map view showing all places
                            CirclePlacesMapView(
                                places: places,
                                mapCenter: $mapCenter,
                                mapZoom: mapZoom,
                                onPlaceTapped: { place in
                                    selectedPlace = place
                                },
                                onPOITapped: { placeID, name, location in
                                    selectedPOI = (placeID, name, location)
                                    showingQuickAddPlace = true
                                }
                            )
                            .frame(height: 400)
                            .cornerRadius(10)
                            .padding(.horizontal)
                        } else {
                            // List view with drag and drop
                            ZStack {
                                List {
                                    ForEach(places) { place in
                                    PlaceRow(place: place) {
                                        selectedPlace = place
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            deletePlace(place)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        
                                        Button {
                                            placeToEdit = place
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                                }
                                .onMove { indices, newOffset in
                                    // Don't allow moves while another update is in progress
                                    guard !isUpdatingOrder else { return }
                                    
                                    places.move(fromOffsets: indices, toOffset: newOffset)
                                    updatePlaceOrder()
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .environment(\.editMode, .constant(.active))
                            .disabled(isUpdatingOrder)
                            .opacity(isUpdatingOrder ? 0.6 : 1.0)
                                
                                // Overlay to show updating status
                                if isUpdatingOrder {
                                    VStack {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(1.2)
                                        Text("Updating order...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.top, 8)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.black.opacity(0.1))
                                }
                            }
                        }
                    }
                }
                .padding(.top)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingShareSheet = true }) {
                        Label("Share Circle", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: { showingEditCircle = true }) {
                        Label("Edit Circle", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive, action: { showingDeleteAlert = true }) {
                        Label("Delete Circle", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable {
            // Don't refresh while updating order
            guard !isUpdatingOrder else { return }
            await fetchPlaces()
        }
        .onAppear {
            Task {
                await fetchPlaces()
            }
            updateMapCenter()
        }
        .sheet(isPresented: $showingAddPlace) {
            AddPlaceViewGoogle(circle: circle, onPlaceAdded: { newPlace in
                places.append(newPlace)
            })
            .environmentObject(placeManager)
        }
        .sheet(isPresented: $showingEditCircle) {
            EditCircleView(circle: circle) { updatedCircle in
                circle = updatedCircle
            }
            .environmentObject(circleManager)
        }
        .sheet(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
                .environmentObject(placeManager)
        }
        .sheet(item: $placeToEdit) { place in
            EditPlaceView(
                place: place,
                onUpdate: { updatedPlace in
                    // Update the local places array
                    if let index = places.firstIndex(where: { $0.id == place.id }) {
                        places[index] = updatedPlace
                    }
                    placeToEdit = nil
                }
            )
            .environmentObject(placeManager)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: circleManager.shareCircle(circle))
        }
        .sheet(isPresented: $showingQuickAddPlace) {
            if let poi = selectedPOI {
                QuickAddPlaceView(
                    circle: circle,
                    placeID: poi.placeID,
                    placeName: poi.name,
                    location: poi.location,
                    onPlaceAdded: { newPlace in
                        places.append(newPlace)
                        showingQuickAddPlace = false
                        selectedPOI = nil
                    },
                    onCancel: {
                        showingQuickAddPlace = false
                        selectedPOI = nil
                    }
                )
                .environmentObject(placeManager)
            }
        }
        .alert("Delete Circle", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCircle()
            }
        } message: {
            Text("Are you sure you want to delete this circle? This action cannot be undone.")
        }
        .overlay(
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    // Map toggle floating button
                    if !places.isEmpty {
                        Button(action: { 
                            showingMapView.toggle()
                            print("FAB Map toggle pressed")
                        }) {
                            Image(systemName: showingMapView ? "list.bullet" : "map.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.green)
                                .clipShape(SwiftUI.Circle())
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 8)
                    }
                    
                    // Add place button
                    Button(action: { showingAddPlace = true }) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(circlesBlue)
                            .clipShape(SwiftUI.Circle())
                            .shadow(radius: 4)
                    }
                    .padding(.trailing)
                }
                .padding(.bottom)
            }
        )
    }
    
    private var privacyIcon: String {
        switch circle.privacy {
        case .public: return "globe"
        case .friends: return "person.2"
        case .private: return "lock"
        }
    }
    
    private var categoryIcon: String {
        switch circle.category {
        case .travel: return "airplane.departure"
        case .food: return "fork.knife.circle.fill"
        case .services: return "wrench.and.screwdriver.fill"
        case .shopping: return "bag.fill"
        case .healthcare: return "heart.text.square.fill"
        case .entertainment: return "music.note.tv.fill"
        case .other: return "square.stack.3d.up.fill"
        }
    }
    
    private func fetchPlaces() async {
        // Don't fetch while updating order to prevent race conditions
        guard !isUpdatingOrder else { 
            print("⏸️ Skipping fetch - order update in progress")
            return 
        }
        
        do {
            let fetchedPlaces = try await placeManager.fetchPlaces(for: circle.id)
            print("📥 Fetched \(fetchedPlaces.count) places with IDs: \(fetchedPlaces.map { $0.id })")
            await MainActor.run {
                self.places = fetchedPlaces
                self.isLoadingPlaces = false
            }
        } catch {
            print("Failed to fetch places: \(error)")
            await MainActor.run {
                self.isLoadingPlaces = false
            }
        }
    }
    
    private func deleteCircle() {
        Task {
            do {
                try await circleManager.deleteCircle(circle)
                // Navigation will be handled by the circle manager
            } catch {
                print("Failed to delete circle: \(error)")
            }
        }
    }
    
    private func deletePlace(_ place: Place) {
        Task {
            do {
                try await placeManager.deletePlace(place)
                // Remove from local array
                await MainActor.run {
                    places.removeAll { $0.id == place.id }
                }
            } catch {
                print("Failed to delete place: \(error)")
            }
        }
    }
    
    private func updatePlaceOrder() {
        // Cancel any pending update
        orderUpdateTask?.cancel()
        
        // Create a new update task with a small delay to debounce rapid changes
        orderUpdateTask = Task {
            // Small delay to debounce rapid reordering
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check if task was cancelled
            if Task.isCancelled { return }
            
            await MainActor.run {
                isUpdatingOrder = true
            }
            
            // Store the current order in case we need to revert
            let previousOrder = places
            
            do {
                // Create an array of place IDs in the new order
                let orderedPlaceIds = places.map { $0.id }
                
                // Call the API to update the order
                print("📤 Sending order update with IDs: \(orderedPlaceIds)")
                try await PlaceService.shared.updatePlaceOrder(circleId: circle.id, placeIds: orderedPlaceIds)
                
                // Success! The order has been saved
                print("✅ Place order updated successfully")
                
                // The order is now persisted on the server
                // The local places array already reflects the new order
                
                // Update map if in map view
                if showingMapView {
                    await MainActor.run {
                        updateMapCenter()
                    }
                }
            } catch {
                print("❌ Failed to update place order: \(error)")
                // Revert the changes locally without fetching from server
                await MainActor.run {
                    // Try to revert to the previous order
                    if !previousOrder.isEmpty {
                        self.places = previousOrder
                    } else {
                        // If we don't have a previous order, fetch from server
                        Task {
                            await fetchPlaces()
                        }
                    }
                }
            }
            
            await MainActor.run {
                isUpdatingOrder = false
                orderUpdateTask = nil
            }
        }
    }
    
    private func updateMapCenter() {
        // Center map on the average location of all places
        guard !places.isEmpty else { return }
        
        let validPlaces = places.compactMap { place -> CLLocationCoordinate2D? in
            guard let location = place.location?.clLocation else { return nil }
            return location.coordinate
        }
        
        guard !validPlaces.isEmpty else { 
            // If no places have locations, use user's location
            if let userLocation = LocationService.shared.lastKnownLocation {
                mapCenter = userLocation.coordinate
            }
            return 
        }
        
        let totalLat = validPlaces.reduce(0) { $0 + $1.latitude }
        let totalLon = validPlaces.reduce(0) { $0 + $1.longitude }
        
        mapCenter = CLLocationCoordinate2D(
            latitude: totalLat / Double(validPlaces.count),
            longitude: totalLon / Double(validPlaces.count)
        )
        
        // Adjust zoom based on spread of places
        if validPlaces.count > 1 {
            let minLat = validPlaces.map { $0.latitude }.min()!
            let maxLat = validPlaces.map { $0.latitude }.max()!
            let minLon = validPlaces.map { $0.longitude }.min()!
            let maxLon = validPlaces.map { $0.longitude }.max()!
            
            let latDelta = maxLat - minLat
            let lonDelta = maxLon - minLon
            let maxDelta = max(latDelta, lonDelta)
            
            // Calculate appropriate zoom level
            if maxDelta < 0.01 {
                mapZoom = 14
            } else if maxDelta < 0.05 {
                mapZoom = 12
            } else if maxDelta < 0.1 {
                mapZoom = 11
            } else {
                mapZoom = 10
            }
        } else {
            mapZoom = 14
        }
    }
}

struct CircleCoverImage: View {
    let circle: Circle
    @State private var coverImage: UIImage?
    
    var body: some View {
        ZStack {
            if let coverImage = coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 250)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.0, green: 122.0/255.0, blue: 1.0),
                        Color(red: 0.0, green: 122.0/255.0, blue: 1.0).opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 250)
                .overlay(
                    Image(systemName: categoryIcon(for: circle.category.rawValue))
                        .font(.system(size: 80))
                        .foregroundColor(.white.opacity(0.8))
                )
            }
        }
        .onAppear {
            loadCoverImage()
        }
    }
    
    private func loadCoverImage() {
        guard let urlString = circle.coverImage,
              let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.coverImage = image
                }
            }
        }.resume()
    }
    
    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case "travel": return "airplane.departure"
        case "food": return "fork.knife.circle.fill"
        case "services": return "wrench.and.screwdriver.fill"
        case "shopping": return "bag.fill"
        case "healthcare": return "heart.text.square.fill"
        case "entertainment": return "music.note.tv.fill"
        default: return "square.stack.3d.up.fill"
        }
    }
}

struct PlaceRow: View {
    let place: Place
    let onTap: () -> Void
    @State private var showingShareSheet = false
    @EnvironmentObject var placeManager: PlaceManager
    @Environment(\.editMode) var editMode
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Show reorder handle when in edit mode
                if editMode?.wrappedValue == .active {
                    Image(systemName: "line.3.horizontal")
                        .font(.body)
                        .foregroundColor(.gray)
                        .padding(.trailing, 8)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(place.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(place.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: 10) {
                        // Category
                        HStack(spacing: 5) {
                            Image(systemName: placeIcon(for: place.category.rawValue))
                                .font(.caption)
                            Text(place.category.displayName)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        
                        // Rating
                        if let rating = place.rating {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text(String(format: "%.1f", rating))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Button(action: { showingShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: placeManager.sharePlace(place))
        }
    }
    
    private func placeIcon(for category: String) -> String {
        switch category.lowercased() {
        case "restaurant": return "fork.knife.circle.fill"
        case "cafe": return "cup.and.saucer.fill"
        case "bar": return "wineglass.fill"
        case "hotel": return "bed.double.fill"
        case "retail", "shopping": return "bag.fill"
        case "service": return "wrench.and.screwdriver.fill"
        case "attraction": return "star.fill"
        case "entertainment": return "music.note.tv.fill"
        case "healthcare": return "heart.text.square.fill"
        case "fitness": return "figure.walk"
        case "education": return "graduationcap.fill"
        case "outdoor": return "tree.fill"
        case "transport": return "car.fill"
        case "finance": return "dollarsign.circle.fill"
        default: return "mappin.circle.fill"
        }
    }
}

struct EmptyPlacesView: View {
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "map")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No places yet")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Tap the + button to add your first place")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    NavigationView {
        CircleDetailView(circle: Circle(
            id: "1",
            name: "Best Restaurants",
            description: "My favorite places to eat",
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
        ))
        .environmentObject(CircleManager.shared)
        .environmentObject(PlaceManager.shared)
    }
}