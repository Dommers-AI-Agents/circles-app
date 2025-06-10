import SwiftUI

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
                        LazyVStack(spacing: 10) {
                            ForEach(places) { place in
                                PlaceRow(place: place) {
                                    selectedPlace = place
                                }
                                .padding(.horizontal)
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
            await fetchPlaces()
        }
        .onAppear {
            Task {
                await fetchPlaces()
            }
        }
        .sheet(isPresented: $showingAddPlace) {
            AddPlaceView(circle: circle, onPlaceAdded: { newPlace in
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
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: circleManager.shareCircle(circle))
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
                    Button(action: { showingAddPlace = true }) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(circlesBlue)
                            .clipShape(SwiftUI.Circle())
                            .shadow(radius: 4)
                    }
                    .padding()
                }
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
        case .travel: return "airplane"
        case .food: return "fork.knife"
        case .services: return "wrench.and.screwdriver"
        case .shopping: return "bag"
        case .healthcare: return "heart"
        case .entertainment: return "tv"
        case .other: return "circle.grid.3x3"
        }
    }
    
    private func fetchPlaces() async {
        do {
            let fetchedPlaces = try await placeManager.fetchPlaces(for: circle.id)
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
        case "travel": return "airplane"
        case "food": return "fork.knife"
        case "services": return "wrench.and.screwdriver"
        case "shopping": return "bag"
        case "healthcare": return "heart"
        case "entertainment": return "tv"
        default: return "circle.grid.3x3"
        }
    }
}

struct PlaceRow: View {
    let place: Place
    let onTap: () -> Void
    @State private var showingShareSheet = false
    @EnvironmentObject var placeManager: PlaceManager
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(place.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(place.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: 5) {
                        Image(systemName: placeIcon(for: place.category.rawValue))
                            .font(.caption)
                        Text(place.category.displayName)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
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
            ShareSheet(items: placeManager.sharePlace(place))
        }
    }
    
    private func placeIcon(for category: String) -> String {
        switch category.lowercased() {
        case "restaurant": return "fork.knife"
        case "cafe": return "cup.and.saucer"
        case "bar": return "wineglass"
        case "hotel": return "bed.double"
        case "retail", "shopping": return "bag"
        case "service": return "wrench"
        case "attraction": return "star"
        case "entertainment": return "tv"
        case "healthcare": return "heart"
        case "fitness": return "figure.walk"
        case "education": return "graduationcap"
        case "outdoor": return "tree"
        case "transport": return "car"
        case "finance": return "dollarsign.circle"
        default: return "mappin"
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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationView {
        CircleDetailView(circle: Circle(
            id: "1",
            name: "Best Restaurants",
            description: "My favorite places to eat",
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
        ))
        .environmentObject(CircleManager.shared)
        .environmentObject(PlaceManager.shared)
    }
}