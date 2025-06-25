import SwiftUI

struct CirclesHomeView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var circleManager: CircleManager
    @State private var showingCreateCircle = false
    @State private var searchText = ""
    @State private var showingHomeAddressEntry = false
    @State private var showingWorkAddressEntry = false
    @State private var homeAddress = ""
    @State private var workAddress = ""
    @State private var navigateToPlace: Place?
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var filteredCircles: [Circle] {
        if searchText.isEmpty {
            return circleManager.circles
        } else {
            return circleManager.circles.filter { circle in
                circle.name.localizedCaseInsensitiveContains(searchText) ||
                (circle.description ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var floatingActionButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: { showingCreateCircle = true }) {
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
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if circleManager.isLoading && circleManager.circles.isEmpty {
            ProgressView()
                .scaleEffect(1.5)
        }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Quick Access Buttons
                HStack(spacing: 16) {
                    QuickAccessButton(
                        title: "Home",
                        icon: "house.fill",
                        color: circlesBlue,
                        action: handleHomeTapped
                    )
                    
                    QuickAccessButton(
                        title: "Work",
                        icon: "building.fill",
                        color: Color(red: 0.39, green: 0.7, blue: 0.93, alpha: 1.0),
                        action: handleWorkTapped
                    )
                }
                .padding()
                .background(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                
                // Main content
                if circleManager.circles.isEmpty && !circleManager.isLoading {
                    EmptyStateView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 15) {
                            ForEach(filteredCircles) { circle in
                                NavigationLink(destination: CircleDetailView(circle: circle)) {
                                    CircleCard(circle: circle)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }
            }
            
            // Floating action button
            floatingActionButton
        }
        .navigationTitle("My Circles")
        .searchable(text: $searchText, prompt: "Search circles")
        .refreshable {
            await circleManager.fetchCircles()
        }
        .sheet(isPresented: $showingCreateCircle) {
            CreateCircleView()
                .environmentObject(circleManager)
        }
        .onAppear {
            if circleManager.circles.isEmpty {
                Task {
                    await circleManager.fetchCircles()
                }
            }
        }
        .overlay(loadingOverlay)
        .background(
            NavigationLink(
                destination: navigateToPlace.map { PlaceDetailView(place: $0) },
                isActive: .constant(navigateToPlace != nil),
                label: { EmptyView() }
            )
        )
        .alert("Set Home Address", isPresented: $showingHomeAddressEntry) {
            TextField("123 Main St, City, State", text: $homeAddress)
            Button("Cancel", role: .cancel) { }
            Button("Save") { saveHomeAddress() }
        }
        .alert("Set Work Address", isPresented: $showingWorkAddressEntry) {
            TextField("123 Main St, City, State", text: $workAddress)
            Button("Cancel", role: .cancel) { }
            Button("Save") { saveWorkAddress() }
        }
        .onAppear {
            loadSavedAddresses()
        }
    }
    
    private func handleHomeTapped() {
        let savedAddress = UserDefaults.standard.string(forKey: "userHomeAddress")
        if let address = savedAddress, !address.isEmpty {
            navigateToQuickAccessPlace(type: "Home", address: address)
        } else {
            showingHomeAddressEntry = true
        }
    }
    
    private func handleWorkTapped() {
        let savedAddress = UserDefaults.standard.string(forKey: "userWorkAddress")
        if let address = savedAddress, !address.isEmpty {
            navigateToQuickAccessPlace(type: "Work", address: address)
        } else {
            showingWorkAddressEntry = true
        }
    }
    
    private func saveHomeAddress() {
        guard !homeAddress.isEmpty else { return }
        UserDefaults.standard.set(homeAddress, forKey: "userHomeAddress")
        navigateToQuickAccessPlace(type: "Home", address: homeAddress)
    }
    
    private func saveWorkAddress() {
        guard !workAddress.isEmpty else { return }
        UserDefaults.standard.set(workAddress, forKey: "userWorkAddress")
        navigateToQuickAccessPlace(type: "Work", address: workAddress)
    }
    
    private func loadSavedAddresses() {
        homeAddress = UserDefaults.standard.string(forKey: "userHomeAddress") ?? ""
        workAddress = UserDefaults.standard.string(forKey: "userWorkAddress") ?? ""
    }
    
    private func navigateToQuickAccessPlace(type: String, address: String) {
        let place = Place(
            id: type.lowercased() + "-place",
            name: type,
            description: "My \(type.lowercased()) address",
            address: address,
            location: GeoLocation(type: "Point", coordinates: [0, 0]),
            website: nil,
            phone: nil,
            googlePlaceId: nil,
            photos: nil,
            category: type == "Home" ? .other : .service,
            rating: nil,
            notes: nil,
            tags: [type.lowercased()],
            reviews: [],
            openingHours: nil,
            priceLevel: nil,
            circleId: "",
            addedBy: authManager.currentUser?.id ?? "",
            privacy: .private,
            createdAt: Date(),
            updatedAt: Date()
        )
        navigateToPlace = place
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            
            Text("No Circles Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create your first circle to start saving and sharing your favorite places")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

struct CircleCard: View {
    let circle: Circle
    @State private var coverImage: UIImage?
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @EnvironmentObject var circleManager: CircleManager
    
    private var placeholderGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.0, green: 122.0/255.0, blue: 1.0),
                Color(red: 0.0, green: 122.0/255.0, blue: 1.0).opacity(0.7)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 200)
        .overlay(
            Image(systemName: categoryIcon(for: circle.category.rawValue))
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.8))
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image or placeholder
            ZStack {
                if let coverImage = coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                } else {
                    placeholderGradient
                }
            }
            
            // Circle info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(circle.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        // Show owner for shared circles
                        if circle.isSharedWithMe == true {
                            HStack(spacing: 4) {
                                Image(systemName: "person.crop.circle")
                                    .font(.caption2)
                                Text("Shared by \(circle.displayOwnerName)")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                    
                    // Privacy indicator
                    Image(systemName: privacyIcon(for: circle.privacy.rawValue))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let description = circle.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    Label("\(circle.places?.count ?? 0)", systemImage: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Share button
                    Button(action: {
                        prepareShareItems()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                            Text("Share")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.0, green: 122.0/255.0, blue: 1.0))
                        .cornerRadius(15)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text(circle.category.displayName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(12)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .onAppear {
            loadCoverImage()
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: shareItems)
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
    
    private func prepareShareItems() {
        // Get base share items from CircleManager
        shareItems = circleManager.shareCircle(circle)
        
        // If we have a cover image, add it and show share sheet
        // Otherwise, try to load it first
        if let coverImage = coverImage {
            shareItems.append(coverImage)
            showingShareSheet = true
        } else if let urlString = circle.coverImage,
                  let url = URL(string: urlString) {
            // Load image asynchronously then show share sheet
            URLSession.shared.dataTask(with: url) { data, _, _ in
                DispatchQueue.main.async {
                    if let data = data, let image = UIImage(data: data) {
                        self.shareItems.append(image)
                    }
                    self.showingShareSheet = true
                }
            }.resume()
        } else {
            // No image, just show share sheet with text
            showingShareSheet = true
        }
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
    
    private func privacyIcon(for privacy: String) -> String {
        switch privacy.lowercased() {
        case "public": return "globe"
        case "friends": return "person.2"
        case "private": return "lock"
        default: return "questionmark.circle"
        }
    }
}

struct QuickAccessButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(color)
            .cornerRadius(12)
        }
    }
}

#Preview {
    NavigationView {
        CirclesHomeView()
            .environmentObject(AuthManager.shared)
            .environmentObject(CircleManager.shared)
    }
}