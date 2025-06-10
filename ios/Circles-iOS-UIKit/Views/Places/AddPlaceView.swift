import SwiftUI
import MapKit

struct AddPlaceView: View {
    let circle: Circle
    let onPlaceAdded: (Place) -> Void
    
    @EnvironmentObject var placeManager: PlaceManager
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [MKLocalSearchCompletion] = []
    @State private var selectedResult: MKLocalSearchCompletion?
    @State private var selectedMapItem: MKMapItem?
    @State private var customName = ""
    @State private var notes = ""
    @State private var selectedCategory = "other"
    @State private var selectedPrivacy = "followCircle"
    @State private var isSearching = false
    @State private var showingMap = true
    @State private var isAddingPlace = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    private let searchCompleter = MKLocalSearchCompleter()
    @State private var searchCompleterDelegate: SearchCompleterDelegate?
    
    private let categories = [
        ("restaurant", "Restaurant", "fork.knife"),
        ("cafe", "Cafe", "cup.and.saucer"),
        ("bar", "Bar", "wineglass"),
        ("hotel", "Hotel", "bed.double"),
        ("retail", "Retail", "bag"),
        ("service", "Service", "wrench"),
        ("attraction", "Attraction", "star"),
        ("entertainment", "Entertainment", "tv"),
        ("healthcare", "Healthcare", "heart"),
        ("fitness", "Fitness", "figure.walk"),
        ("education", "Education", "graduationcap"),
        ("outdoor", "Outdoor", "tree"),
        ("transport", "Transport", "car"),
        ("finance", "Finance", "dollarsign.circle"),
        ("other", "Other", "mappin")
    ]
    
    private let privacyOptions = [
        ("followCircle", "Follow Circle Privacy", "circle", "Use the same privacy setting as the circle"),
        ("public", "Public", "globe", "Anyone can see this place"),
        ("friends", "Friends Only", "person.2", "Only friends can see this place"),
        ("private", "Private", "lock", "Only you can see this place")
    ]
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search for a place or address...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: searchText) { newValue in
                            searchPlaces(query: newValue)
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                
                // Map or form view
                if showingMap && selectedMapItem == nil {
                    // Map view with search results
                    ZStack(alignment: .top) {
                        Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: mapAnnotations) { item in
                            MapAnnotation(coordinate: item.coordinate) {
                                Button(action: { selectSearchResult(item.completion) }) {
                                    VStack {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.red)
                                        Text(item.title)
                                            .font(.caption)
                                            .padding(4)
                                            .background(Color.white.opacity(0.9))
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                        
                        // Search results list
                        if !searchResults.isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(searchResults, id: \.self) { result in
                                        Button(action: { selectSearchResult(result) }) {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(result.title)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                Text(result.subtitle)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .background(Color(.systemBackground))
                                        
                                        Divider()
                                    }
                                }
                            }
                            .frame(maxHeight: 300)
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .padding()
                        }
                    }
                } else {
                    // Place details form
                    Form {
                        if let mapItem = selectedMapItem {
                            Section(header: Text("Place Information")) {
                                // Place name
                                VStack(alignment: .leading) {
                                    Text("Name")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if isAddressResult {
                                        TextField("Enter a name for this place", text: $customName)
                                    } else {
                                        Text(mapItem.name ?? "Unknown Place")
                                    }
                                }
                                
                                // Address
                                VStack(alignment: .leading) {
                                    Text("Address")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formattedAddress)
                                        .font(.body)
                                }
                                
                                // Notes
                                VStack(alignment: .leading) {
                                    Text("Notes (optional)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextEditor(text: $notes)
                                        .frame(minHeight: 60)
                                }
                            }
                            
                            // Category selection
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
                            
                            // Privacy selection
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
                    }
                }
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
                    if selectedMapItem != nil {
                        Button("Add") {
                            addPlace()
                        }
                        .disabled(isAddingPlace || (isAddressResult && customName.isEmpty))
                    }
                }
            }
        }
        .onAppear {
            setupSearchCompleter()
            requestLocationPermission()
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
    
    private var isAddressResult: Bool {
        selectedResult?.subtitle.isEmpty ?? false
    }
    
    private var formattedAddress: String {
        guard let mapItem = selectedMapItem else { return "" }
        
        let placemark = mapItem.placemark
        var addressComponents: [String] = []
        
        if let subThoroughfare = placemark.subThoroughfare {
            addressComponents.append(subThoroughfare)
        }
        if let thoroughfare = placemark.thoroughfare {
            addressComponents.append(thoroughfare)
        }
        if let locality = placemark.locality {
            addressComponents.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            addressComponents.append(administrativeArea)
        }
        if let postalCode = placemark.postalCode {
            addressComponents.append(postalCode)
        }
        
        return addressComponents.joined(separator: ", ")
    }
    
    private var mapAnnotations: [MapAnnotationItem] {
        searchResults.compactMap { result in
            MapAnnotationItem(completion: result)
        }
    }
    
    private func setupSearchCompleter() {
        searchCompleterDelegate = SearchCompleterDelegate { results in
            DispatchQueue.main.async {
                self.searchResults = results
            }
        }
        searchCompleter.delegate = searchCompleterDelegate
        searchCompleter.region = region
        searchCompleter.resultTypes = [.address, .pointOfInterest]
    }
    
    private func requestLocationPermission() {
        LocationService.shared.requestAuthorization()
        LocationService.shared.getCurrentLocation { location in
            if let location = location {
                DispatchQueue.main.async {
                    self.region = MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                }
            }
        }
    }
    
    private func searchPlaces(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        searchCompleter.queryFragment = query
    }
    
    private func selectSearchResult(_ result: MKLocalSearchCompletion) {
        selectedResult = result
        
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { response, error in
            if let mapItem = response?.mapItems.first {
                DispatchQueue.main.async {
                    self.selectedMapItem = mapItem
                    self.region = MKCoordinateRegion(
                        center: mapItem.placemark.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    
                    // Clear custom name field for addresses
                    if self.isAddressResult {
                        self.customName = ""
                    }
                    
                    // Auto-select category based on MKMapItem category
                    if let category = self.detectCategory(from: mapItem) {
                        self.selectedCategory = category
                    }
                }
            }
        }
    }
    
    private func detectCategory(from mapItem: MKMapItem) -> String? {
        guard let category = mapItem.pointOfInterestCategory else { return nil }
        
        switch category {
        case .restaurant: return "restaurant"
        case .cafe: return "cafe"
        case .nightlife: return "bar"
        case .hotel: return "hotel"
        case .store: return "retail"
        case .hospital: return "healthcare"
        // case .fitness: return "fitness" // Not available in MKPointOfInterestCategory
        case .school, .university: return "education"
        case .park: return "outdoor"
        case .gasStation, .parking, .publicTransport: return "transport"
        case .bank, .atm: return "finance"
        case .theater, .movieTheater, .museum, .stadium: return "entertainment"
        default: return nil
        }
    }
    
    private func addPlace() {
        guard let mapItem = selectedMapItem else { return }
        
        // Validate name for address results
        if isAddressResult && customName.isEmpty {
            errorMessage = "Please enter a name for this place"
            showingError = true
            return
        }
        
        isAddingPlace = true
        
        let placeName = isAddressResult ? customName : (mapItem.name ?? "Unknown Place")
        
        Task {
            do {
                let addedPlace = try await placeManager.addPlace(
                    to: circle,
                    name: placeName,
                    description: nil,
                    address: formattedAddress,
                    category: PlaceCategory(rawValue: selectedCategory) ?? .other
                )
                await MainActor.run {
                    onPlaceAdded(addedPlace)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isAddingPlace = false
                }
            }
        }
    }
}

// Helper struct for map annotations
struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let completion: MKLocalSearchCompletion
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 0, longitude: 0) // Will be updated by search
    }
    
    var title: String {
        completion.title
    }
}

// Search completer delegate
class SearchCompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    let onResults: ([MKLocalSearchCompletion]) -> Void
    
    init(onResults: @escaping ([MKLocalSearchCompletion]) -> Void) {
        self.onResults = onResults
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onResults(completer.results)
    }
}

#Preview {
    AddPlaceView(
        circle: Circle(
            id: "1",
            name: "Test Circle",
            description: nil,
            coverImage: nil,
            owner: "user1",
            places: [],
            privacy: .friends,
            category: .food,
            location: nil,
            tags: nil,
            sharedWith: nil,
            followers: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onPlaceAdded: { _ in }
    )
    .environmentObject(PlaceManager.shared)
}