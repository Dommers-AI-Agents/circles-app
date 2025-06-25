import SwiftUI
import GoogleMaps
import GooglePlaces
import CoreLocation

struct AddPlaceViewGoogle: View {
    let circle: Circle
    let onPlaceAdded: (Place) -> Void
    
    @EnvironmentObject var placeManager: PlaceManager
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var searchViewModel = GooglePlaceSearchViewModel()
    @State private var selectedGooglePlace: GooglePlaceDetails?
    @State private var notes = ""
    @State private var selectedCategory: String?
    @State private var selectedPrivacy = "followCircle"
    @State private var isAddingPlace = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var loadedPhotos: [UIImage] = []
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
    @State private var mapZoom: Float = 12.0
    @State private var mapMarkers: [GoogleMapMarker] = []
    @State private var selectedMarker: GoogleMapMarker?
    @State private var showSearchResults = false
    @State private var hasRequestedLocation = false
    @State private var isLoadingLocation = false
    @State private var showingManualEntry = false
    @State private var isCategorySearch = false
    @State private var isMapSearchEnabled = false
    @State private var lastSearchRegion: GMSVisibleRegion?
    @State private var mapIdleTimer: Timer?
    @State private var isSearchingCategory = false
    @State private var currentCategorySearch = ""
    
    private let privacyOptions = [
        ("followCircle", "Follow Circle Privacy", "circle", "Use the same privacy setting as the circle"),
        ("public", "Public", "globe", "Anyone can see this place"),
        ("friends", "Friends Only", "person.2", "Only friends can see this place"),
        ("private", "Private", "lock", "Only you can see this place")
    ]
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    private let placeCategories = [
        ("restaurant", "Restaurants", "fork.knife", "restaurant"),
        ("cafe", "Cafes", "cup.and.saucer", "cafe coffee"),
        ("bar", "Bars", "wineglass", "bar pub"),
        ("shopping", "Shopping", "bag", "shopping mall store"),
        ("hotel", "Hotels", "bed.double", "hotel"),
        ("attraction", "Attractions", "star", "tourist attraction"),
        ("service", "Services", "wrench.and.screwdriver", "service"),
        ("outdoor", "Outdoors", "tree", "park")
    ]
    
    var body: some View {
        NavigationView {
            if let place = selectedGooglePlace {
                // Show place details form
                placeDetailsForm(for: place)
            } else {
                // Show split view with search sidebar and map
                searchAndMapView
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Force single column layout
        .onReceive(searchViewModel.$selectedPlace) { place in
            if let place = place {
                selectedGooglePlace = place
                // Auto-select category based on Google Place types
                selectedCategory = determinePlaceCategory(from: place.types).rawValue
            }
        }
        .onReceive(searchViewModel.$searchResults) { results in
            updateMapMarkers(from: results)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .overlay(
            loadingOverlay
        )
        .sheet(isPresented: $showingManualEntry) {
            ManualAddressEntryView { address in
                showingManualEntry = false
                searchViewModel.createPlaceFromAddress(address)
            }
        }
    }
    
    @ViewBuilder
    private var searchAndMapView: some View {
        ZStack(alignment: .top) {
            // Map fills the entire view
            mapView
            
            // Floating search bar and selected place card
            VStack(spacing: 0) {
                // Search bar and categories container
                VStack(spacing: 10) {
                    // Search bar
                    searchBarView
                        .background(Material.regular)
                        .cornerRadius(10)
                        .shadow(radius: 3)
                    
                    // Category buttons
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(placeCategories, id: \.0) { category in
                                CategoryButton(
                                    title: category.1,
                                    icon: category.2,
                                    isSelected: selectedCategory == category.0,
                                    action: {
                                        if selectedCategory == category.0 {
                                            selectedCategory = nil
                                            isCategorySearch = false
                                            clearSearchResults()
                                        } else {
                                            selectedCategory = category.0
                                            isCategorySearch = true
                                            searchByCategory(category.3)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .background(Material.ultraThin)
                
                // Map search toggle
                HStack {
                    Text("Search as map moves")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $isMapSearchEnabled)
                        .labelsHidden()
                        .scaleEffect(0.8)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Material.ultraThin)
                
                // Show selected place info if any
                if let marker = selectedMarker {
                    selectedPlaceCard(marker: marker)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: selectedMarker)
        }
        .navigationTitle("Add Place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Manual Entry") {
                    showingManualEntry = true
                }
                .foregroundColor(circlesBlue)
            }
        }
        .onAppear {
            requestUserLocation()
        }
    }
    
    @ViewBuilder
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search for a place...", text: $searchViewModel.searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .onSubmit {
                    // Manual search - not a category search
                    isCategorySearch = false
                    selectedCategory = nil
                    searchViewModel.search()
                }
            
            if !searchViewModel.searchText.isEmpty {
                Button(action: { 
                    searchViewModel.searchText = ""
                    // Only clear category search if we're not in a category search
                    if !isCategorySearch {
                        clearSearchResults()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    @ViewBuilder
    private func selectedPlaceCard(marker: GoogleMapMarker) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(marker.title)
                .font(.headline)
                .lineLimit(1)
            
            if let subtitle = marker.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                Button("Cancel") {
                    withAnimation {
                        selectedMarker = nil
                    }
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Button("Select This Place") {
                    if let placeID = marker.placeID {
                        searchViewModel.selectPlace(byID: placeID)
                    }
                }
                .foregroundColor(circlesBlue)
                .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .padding()
        .background(Material.regular)
        .cornerRadius(10)
        .shadow(radius: 3)
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var searchResultsView: some View {
        if searchViewModel.isSearching {
            ProgressView("Searching...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !searchViewModel.searchResults.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(searchViewModel.searchResults, id: \.placeID) { prediction in
                        PlacePredictionRow(prediction: prediction) {
                            searchViewModel.selectPlace(prediction)
                        }
                        
                        Divider()
                    }
                }
            }
        } else if !searchViewModel.searchText.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                
                Text("No places found")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Try searching for a different place")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Divider()
                    .padding(.vertical, 10)
                
                Button(action: {
                    // Create a place with just the address
                    searchViewModel.createPlaceFromAddress(searchViewModel.searchText)
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add \"\(searchViewModel.searchText)\" anyway")
                    }
                    .foregroundColor(circlesBlue)
                    .font(.headline)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            VStack(spacing: 20) {
                Image(systemName: "map")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                
                Text("Search for places")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Find restaurants, cafes, shops, and more")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
    
    @ViewBuilder
    private var mapView: some View {
        GoogleMapView(
            center: $mapCenter,
            zoom: mapZoom,
            markers: mapMarkers,
            showsUserLocation: true,
            onMarkerTapped: { marker in
                // Show the selected place card
                withAnimation {
                    selectedMarker = marker
                }
            },
            showUserLocationCircle: false, // Never show the search radius circle
            onPOITapped: { placeID, name, location in
                // User tapped on a point of interest
                handlePOITap(placeID: placeID, name: name, location: location)
            },
            onCameraDidIdle: { cameraPosition in
                // Update map center
                mapCenter = cameraPosition.target
                mapZoom = cameraPosition.zoom
                
                // Camera stopped moving, trigger search if enabled
                if isMapSearchEnabled {
                    if isCategorySearch && selectedCategory != nil {
                        // Re-search the category in the new area
                        if let category = placeCategories.first(where: { $0.0 == selectedCategory }) {
                            searchByCategory(category.3)
                        }
                    } else if !searchViewModel.searchText.isEmpty {
                        // Re-run the current search in the new area
                        searchViewModel.search()
                    }
                }
            }
        )
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        Group {
            if isAddingPlace {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                ProgressView("Adding Place...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
            } else if searchViewModel.isLoadingDetails {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                ProgressView("Loading place details...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
            } else if isLoadingLocation {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                ProgressView("Getting your location...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
            } else if isSearchingCategory {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                ProgressView("Searching for \(currentCategorySearch)...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
            }
        }
    }
    
    private func placeDetailsForm(for place: GooglePlaceDetails) -> some View {
        Form {
            placeInformationSection(for: place)
            categorySection()
            notesSection()
            privacySection()
        }
        .navigationTitle("Add Place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") {
                    selectedGooglePlace = nil
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") {
                    addPlace()
                }
                .disabled(isAddingPlace)
            }
        }
        .onAppear {
            loadPlacePhotos()
            // Auto-select category if we have place details
            if let place = selectedGooglePlace {
                selectedCategory = determinePlaceCategory(from: place.types).rawValue
            }
        }
    }
    
    private func loadPlacePhotos() {
        guard let place = selectedGooglePlace else { return }
        
        // Load up to 3 photos
        let photosToLoad = Array(place.photos.prefix(3))
        
        for photoRef in photosToLoad {
            GooglePlacesService.shared.loadPlacePhoto(photoReference: photoRef) { image in
                if let image = image {
                    DispatchQueue.main.async {
                        self.loadedPhotos.append(image)
                    }
                }
            }
        }
    }
    
    // MARK: - Section Views
    
    @ViewBuilder
    private func placeInformationSection(for place: GooglePlaceDetails) -> some View {
        Section(header: Text("Place Information")) {
            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(place.name)
                    .font(.body)
            }
            
            // Address
            if let address = place.address {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(address)
                        .font(.body)
                }
            }
            
            // Rating
            if let rating = place.rating {
                HStack {
                    Text("Rating")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    PlaceRatingView(rating: rating, totalRatings: place.userRatingsTotal)
                }
            }
            
            // Price Level
            if let priceLevel = place.priceLevel {
                HStack {
                    Text("Price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(priceLevel.displaySymbol)
                        .font(.body)
                        .foregroundColor(.green)
                }
            }
            
            // Hours
            if let _ = place.openingHours {
                HStack {
                    Text("Status")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let isOpen = place.isOpen {
                        Text(isOpen ? "Open Now" : "Closed")
                            .font(.body)
                            .foregroundColor(isOpen ? .green : .red)
                    } else {
                        Text("Hours not available")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Phone
            if let phone = place.phoneNumber {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(phone)
                        .font(.body)
                }
            }
            
            // Website
            if let website = place.website {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Website")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(website.absoluteString)
                        .font(.body)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }
            }
            
            // Photos
            if !loadedPhotos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Photos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(loadedPhotos.indices, id: \.self) { index in
                                Image(uiImage: loadedPhotos[index])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 100, height: 100)
                                    .cornerRadius(8)
                                    .clipped()
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func categorySection() -> some View {
        Section(header: Text("Category")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PlaceCategory.allCases, id: \.self) { category in
                        PlaceCategoryChip(
                            title: category.displayName,
                            isSelected: selectedCategory == category.rawValue,
                            action: {
                                selectedCategory = category.rawValue
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    @ViewBuilder
    private func notesSection() -> some View {
        Section(header: Text("Personal Notes")) {
            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .placeholder(when: notes.isEmpty) {
                    Text("Add your thoughts about this place...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
        }
    }
    
    @ViewBuilder
    private func privacySection() -> some View {
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
    
    private func clearSearchResults() {
        mapMarkers = []
        selectedMarker = nil
        showSearchResults = false
        // Don't clear isCategorySearch here - it should only be cleared when deselecting a category
    }
    
    private func updateMapMarkers(from predictions: [GooglePlacePrediction]) {
        // Clear existing markers
        mapMarkers = []
        selectedMarker = nil
        
        guard !predictions.isEmpty else { return }
        
        // Fetch place details for each prediction to get coordinates
        let placesClient = GMSPlacesClient.shared()
        let topResults = Array(predictions.prefix(20)) // Show up to 20 results like Google Maps
        
        var fetchedMarkers: [GoogleMapMarker] = []
        let dispatchGroup = DispatchGroup()
        
        for prediction in topResults {
            dispatchGroup.enter()
            
            let fields: GMSPlaceField = [.coordinate, .name, .formattedAddress, .placeID, .types]
            
            placesClient.fetchPlace(fromPlaceID: prediction.placeID, placeFields: fields, sessionToken: nil) { place, error in
                if let place = place {
                    // Determine category from place types
                    let category = self.determinePlaceCategory(from: place.types ?? [])
                    
                    let marker = GoogleMapMarker(
                        coordinate: place.coordinate,
                        title: place.name ?? "Unknown Place",
                        subtitle: place.formattedAddress,
                        placeID: place.placeID,
                        category: category
                    )
                    
                    fetchedMarkers.append(marker)
                }
                dispatchGroup.leave()
            }
        }
        
        // Once all places are fetched, update the map
        dispatchGroup.notify(queue: .main) {
            self.mapMarkers = fetchedMarkers
            self.showSearchResults = true
            
            // For category searches, don't change the map view
            // For regular searches, fit to markers
            if !self.isCategorySearch && !fetchedMarkers.isEmpty {
                self.fitMapToMarkers(fetchedMarkers)
            } else if self.isCategorySearch {
                // For category searches, just ensure we're showing all markers
                print("Category search completed with \(fetchedMarkers.count) markers")
            }
        }
    }
    
    private func fitMapToMarkers(_ markers: [GoogleMapMarker]) {
        guard !markers.isEmpty else { return }
        
        // For category searches, don't change the map view at all
        if isCategorySearch {
            return
        }
        
        var markersToFit = markers
        var minLat: Double = 0
        var maxLat: Double = 0
        var minLon: Double = 0
        var maxLon: Double = 0
        
        // If searching and have user location, prioritize results near user
        if let userLocation = LocationService.shared.lastKnownLocation {
            // Find markers within reasonable distance (approx 50km) from user
            let nearbyMarkers = markers.filter { marker in
                let distance = CLLocation(latitude: marker.coordinate.latitude, longitude: marker.coordinate.longitude)
                    .distance(from: CLLocation(latitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude))
                return distance < 50000 // 50km
            }
            
            // If we have nearby results, use those; otherwise use all results
            markersToFit = nearbyMarkers.isEmpty ? markers : nearbyMarkers
        }
        
        // If only one marker, center on it with reasonable zoom
        if markersToFit.count == 1 {
            mapCenter = markersToFit[0].coordinate
            mapZoom = 15.0
            return
        }
        
        // Calculate bounds that include relevant markers
        minLat = markersToFit[0].coordinate.latitude
        maxLat = markersToFit[0].coordinate.latitude
        minLon = markersToFit[0].coordinate.longitude
        maxLon = markersToFit[0].coordinate.longitude
        
        for marker in markersToFit {
            minLat = min(minLat, marker.coordinate.latitude)
            maxLat = max(maxLat, marker.coordinate.latitude)
            minLon = min(minLon, marker.coordinate.longitude)
            maxLon = max(maxLon, marker.coordinate.longitude)
        }
        
        // Calculate center
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        mapCenter = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        
        // Calculate appropriate zoom level
        let latDelta = maxLat - minLat
        let lonDelta = maxLon - minLon
        
        // Add some padding to the bounds (20% on each side)
        let paddedLatDelta = latDelta * 1.4
        let paddedLonDelta = lonDelta * 1.4
        
        // Calculate zoom level based on the span
        // This is an approximation that works well for most cases
        let maxDelta = max(paddedLatDelta, paddedLonDelta)
        
        let zoom: Float
        if maxDelta < 0.001 {
            zoom = 17.0
        } else if maxDelta < 0.005 {
            zoom = 15.0
        } else if maxDelta < 0.01 {
            zoom = 14.0
        } else if maxDelta < 0.05 {
            zoom = 13.0
        } else if maxDelta < 0.1 {
            zoom = 12.0
        } else if maxDelta < 0.5 {
            zoom = 11.0
        } else {
            zoom = 10.0
        }
        
        mapZoom = zoom
    }
    
    private func determinePlaceCategory(from types: [String]) -> PlaceCategory {
        // Map Google Place types to our categories
        // Check for specific types first for better accuracy
        
        // Restaurant & Food
        if types.contains("restaurant") || types.contains("food") || 
           types.contains("meal_delivery") || types.contains("meal_takeaway") {
            return .restaurant
        }
        
        // Cafe
        if types.contains("cafe") || types.contains("coffee_shop") || 
           types.contains("bakery") {
            return .cafe
        }
        
        // Bar
        if types.contains("bar") || types.contains("night_club") || 
           types.contains("liquor_store") || types.contains("brewery") {
            return .bar
        }
        
        // Shopping & Retail
        if types.contains("store") || types.contains("shopping_mall") || 
           types.contains("clothing_store") || types.contains("book_store") ||
           types.contains("electronics_store") || types.contains("grocery_or_supermarket") ||
           types.contains("department_store") || types.contains("convenience_store") {
            return .retail
        }
        
        // Hotel & Lodging
        if types.contains("lodging") || types.contains("hotel") || 
           types.contains("motel") || types.contains("resort") {
            return .hotel
        }
        
        // Attractions
        if types.contains("tourist_attraction") || types.contains("museum") || 
           types.contains("art_gallery") || types.contains("amusement_park") ||
           types.contains("aquarium") || types.contains("zoo") || 
           types.contains("stadium") || types.contains("point_of_interest") {
            return .attraction
        }
        
        // Outdoor
        if types.contains("park") || types.contains("campground") || 
           types.contains("natural_feature") || types.contains("hiking_area") ||
           types.contains("beach") || types.contains("lake") {
            return .outdoor
        }
        
        // Entertainment
        if types.contains("movie_theater") || types.contains("bowling_alley") || 
           types.contains("casino") || types.contains("arcade") {
            return .entertainment
        }
        
        // Healthcare
        if types.contains("health") || types.contains("hospital") || 
           types.contains("doctor") || types.contains("dentist") || 
           types.contains("pharmacy") || types.contains("veterinary_care") {
            return .healthcare
        }
        
        // Fitness
        if types.contains("gym") || types.contains("fitness_center") || 
           types.contains("yoga_studio") || types.contains("spa") {
            return .fitness
        }
        
        // Services
        if types.contains("car_repair") || types.contains("hair_care") || 
           types.contains("beauty_salon") || types.contains("laundry") ||
           types.contains("bank") || types.contains("atm") || 
           types.contains("post_office") || types.contains("car_wash") {
            return .service
        }
        
        // Transport
        if types.contains("transit_station") || types.contains("train_station") || 
           types.contains("bus_station") || types.contains("airport") ||
           types.contains("gas_station") || types.contains("parking") {
            return .transport
        }
        
        // Education
        if types.contains("school") || types.contains("university") || 
           types.contains("library") {
            return .education
        }
        
        // Finance
        if types.contains("accounting") || types.contains("insurance_agency") || 
           types.contains("real_estate_agency") {
            return .finance
        }
        
        // Default to other
        return .other
    }
    
    private func searchByCategory(_ searchTerm: String) {
        // Don't clear results immediately to avoid flicker
        
        // Mark this as a category search
        isCategorySearch = true
        
        // Show loading state
        isSearchingCategory = true
        currentCategorySearch = searchTerm.split(separator: " ").first.map(String.init) ?? searchTerm
        
        // Calculate visible area radius based on zoom level
        let metersPerPixel = 156543.03392 * cos(mapCenter.latitude * .pi / 180) / pow(2, Double(mapZoom))
        let mapRadiusInMeters = max(metersPerPixel * 500, 2000) // At least 2km radius
        
        print("🔍 Searching for \(searchTerm) at location: \(mapCenter.latitude), \(mapCenter.longitude) with radius: \(mapRadiusInMeters)m")
        
        // Get location context for better search results
        let location = CLLocation(latitude: mapCenter.latitude, longitude: mapCenter.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            var enhancedSearchTerm = searchTerm
            
            if let placemark = placemarks?.first {
                // Add city/area context to search
                if let city = placemark.locality ?? placemark.administrativeArea {
                    enhancedSearchTerm = "\(searchTerm) in \(city)"
                    print("🌆 Enhanced search term: \(enhancedSearchTerm)")
                }
            }
            
            // Use the enhanced search term
            GooglePlacesService.shared.searchPlacesByCategory(
                category: enhancedSearchTerm,
                center: self.mapCenter,
                radiusInMeters: mapRadiusInMeters
            ) { result in
                DispatchQueue.main.async {
                    self.isSearchingCategory = false
                    
                    switch result {
                    case .success(let predictions):
                        if !predictions.isEmpty {
                            print("✅ Found \(predictions.count) results for '\(enhancedSearchTerm)'")
                            let googlePredictions = predictions.map { GooglePlacePrediction(from: $0) }
                            self.searchViewModel.searchResults = googlePredictions
                            self.updateMapMarkers(from: googlePredictions)
                        } else {
                            print("❌ No results for '\(enhancedSearchTerm)'")
                            self.searchViewModel.searchResults = []
                            self.mapMarkers = []
                            
                            // Show a helpful message with the category name
                            let categoryName = self.currentCategorySearch.lowercased()
                            self.errorMessage = "No \(categoryName) found in this area. Try zooming out or moving the map."
                            self.showingError = true
                        }
                        
                    case .failure(let error):
                        print("❌ Error searching: \(error)")
                        self.searchViewModel.searchResults = []
                        self.mapMarkers = []
                        self.errorMessage = "Error searching. Please try again."
                        self.showingError = true
                    }
                }
            }
        }
    }
    
    private func performNearbySearch(type: String, location: CLLocation) {
        // For now, just use a text search with the category name near the location
        let searchQuery = type.replacingOccurrences(of: "_", with: " ")
        searchViewModel.searchText = searchQuery
        searchViewModel.search()
        
        // Also ensure we show the user's location area
        if LocationService.shared.lastKnownLocation != nil {
            // The search results will be shown via updateMapMarkers which already fits to bounds
            // No need to do anything extra here as the search callback will handle it
        }
    }
    
    private func addPlace() {
        guard let googlePlace = selectedGooglePlace else { return }
        
        isAddingPlace = true
        
        // Log the data being sent
        print("📍 Adding place with Google data:")
        print("  - Name: \(googlePlace.name)")
        print("  - Address: \(googlePlace.address ?? "N/A")")
        print("  - Google Place ID: \(googlePlace.placeID)")
        print("  - Rating: \(googlePlace.rating ?? 0)")
        print("  - Price Level: \(googlePlace.priceLevel?.rawValue ?? -1)")
        print("  - Coordinate: \(googlePlace.coordinate.latitude), \(googlePlace.coordinate.longitude)")
        
        Task {
            do {
                var placeData: [String: Any] = [
                    "name": googlePlace.name,
                    "address": googlePlace.address ?? "",
                    "location": [
                        "type": "Point",
                        "coordinates": [googlePlace.coordinate.longitude, googlePlace.coordinate.latitude]
                    ],
                    "googlePlaceId": googlePlace.placeID,
                    "category": selectedCategory ?? "other",
                    "circleId": circle.id,
                    "privacy": selectedPrivacy
                ]
                
                // Add optional fields
                if let website = googlePlace.website {
                    placeData["website"] = website.absoluteString
                }
                if let phone = googlePlace.phoneNumber {
                    placeData["phone"] = phone
                }
                if let rating = googlePlace.rating {
                    placeData["rating"] = rating
                    placeData["userRatingsTotal"] = googlePlace.userRatingsTotal
                }
                if !notes.isEmpty {
                    placeData["notes"] = notes
                }
                if let priceLevel = googlePlace.priceLevel {
                    placeData["priceLevel"] = priceLevel.rawValue
                }
                if !googlePlace.types.isEmpty {
                    placeData["tags"] = googlePlace.types
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
    
    private func requestUserLocation() {
        // First check if we already have a last known location
        if let location = LocationService.shared.lastKnownLocation {
            mapCenter = location.coordinate
            mapZoom = 15.0
            // Still try to get a fresh location in case the user has moved
            if !hasRequestedLocation {
                hasRequestedLocation = true
                LocationService.shared.getCurrentLocation { newLocation in
                    DispatchQueue.main.async {
                        if let newLocation = newLocation {
                            mapCenter = newLocation.coordinate
                        }
                    }
                }
            }
            return
        }
        
        // Prevent multiple requests
        guard !hasRequestedLocation else { return }
        hasRequestedLocation = true
        
        // Request location permissions if needed
        LocationService.shared.requestAuthorization()
        
        // Get current location
        isLoadingLocation = true
        LocationService.shared.getCurrentLocation { location in
            DispatchQueue.main.async {
                isLoadingLocation = false
                if let location = location {
                    mapCenter = location.coordinate
                    mapZoom = 15.0
                } else {
                    // If location is not available, use default or try to get a general location based on IP
                    // For now, we'll keep the default New York location
                    print("📍 Could not get user location, using default")
                }
            }
        }
    }
    
    private func handlePOITap(placeID: String, name: String, location: CLLocationCoordinate2D) {
        // Clear any existing selection
        selectedMarker = nil
        
        // Create a temporary marker for the POI
        let tempMarker = GoogleMapMarker(
            coordinate: location,
            title: name,
            subtitle: "Loading details...",
            placeID: placeID,
            category: .other
        )
        
        // Show loading indicator
        searchViewModel.isLoadingDetails = true
        
        // Fetch place details
        GooglePlacesService.shared.fetchPlaceDetails(placeID: placeID) { result in
            DispatchQueue.main.async {
                searchViewModel.isLoadingDetails = false
                
                switch result {
                case .success(let place):
                    // Create GooglePlaceDetails from the fetched place
                    let placeDetails = GooglePlaceDetails(from: place)
                    selectedGooglePlace = placeDetails
                    
                case .failure(let error):
                    print("Failed to fetch POI details: \(error)")
                    // Still show basic info
                    selectedMarker = tempMarker
                }
            }
        }
    }
    
    private func searchInVisibleRegion(cameraPosition: GMSCameraPosition) {
        // Cancel any pending timer
        mapIdleTimer?.invalidate()
        
        // Set a new timer to avoid too frequent searches
        mapIdleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            // Calculate the span based on zoom level
            // At zoom 15, roughly 1km = 0.009 degrees latitude
            let zoomFactor = pow(2, Double(15 - cameraPosition.zoom))
            let latSpan = 0.02 * zoomFactor // Adjust based on zoom
            let lonSpan = 0.02 * zoomFactor
            
            // Calculate visible region bounds
            let northEast = CLLocationCoordinate2D(
                latitude: cameraPosition.target.latitude + latSpan,
                longitude: cameraPosition.target.longitude + lonSpan
            )
            let southWest = CLLocationCoordinate2D(
                latitude: cameraPosition.target.latitude - latSpan,
                longitude: cameraPosition.target.longitude - lonSpan
            )
            
            // Clear current search text to indicate map search
            searchViewModel.searchText = "Searching in visible area..."
            
            // Perform search in the visible region
            let placesClient = GMSPlacesClient.shared()
            let filter = GMSAutocompleteFilter()
            filter.type = .establishment
            filter.locationRestriction = GMSPlaceRectangularLocationOption(southWest, northEast)
            
            // Use a more comprehensive search query for general area search
            placesClient.findAutocompletePredictions(
                fromQuery: "restaurant cafe bar shopping hotel attraction service park food dining coffee",
                filter: filter,
                sessionToken: nil
            ) { (predictions, error) in
                DispatchQueue.main.async {
                    if let predictions = predictions {
                        print("Found \(predictions.count) places in visible region")
                        let googlePredictions = predictions.map { GooglePlacePrediction(from: $0) }
                        searchViewModel.searchResults = googlePredictions
                        self.updateMapMarkers(from: googlePredictions)
                    } else if let error = error {
                        print("Error searching visible region: \(error)")
                    }
                    
                    // Clear the search text
                    searchViewModel.searchText = ""
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct PlaceCategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? circlesBlue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

struct PlaceRatingView: View {
    let rating: Double
    let totalRatings: Int?
    
    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    Image(systemName: index < Int(rating.rounded()) ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
            }
            
            Text(String(format: "%.1f", rating))
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let total = totalRatings {
                Text("(\(total))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// Extension for placeholder text in TextEditor
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Supporting Types

struct CategoryButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? circlesBlue : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(15)
        }
    }
}

#Preview {
    AddPlaceViewGoogle(
        circle: Circle(
            id: "1",
            name: "Test Circle",
            description: nil,
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
        onPlaceAdded: { _ in }
    )
    .environmentObject(PlaceManager.shared)
}