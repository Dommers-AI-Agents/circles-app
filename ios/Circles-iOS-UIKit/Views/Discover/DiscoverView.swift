import SwiftUI
import MapKit

struct DiscoverView: View {
    @EnvironmentObject var circleManager: CircleManager
    @State private var searchText = ""
    @State private var selectedCategory = "all"
    @State private var showingMap = false
    @State private var publicCircles: [Circle] = []
    @State private var isLoading = false
    
    private let categories = [
        ("all", "All", "circle.grid.3x3"),
        ("travel", "Travel", "airplane"),
        ("food", "Food", "fork.knife"),
        ("services", "Services", "wrench.and.screwdriver"),
        ("shopping", "Shopping", "bag"),
        ("healthcare", "Healthcare", "heart"),
        ("entertainment", "Entertainment", "tv")
    ]
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var filteredCircles: [Circle] {
        var filtered = publicCircles
        
        // Filter by category
        if selectedCategory != "all" {
            filtered = filtered.filter { $0.category.rawValue == selectedCategory }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { circle in
                circle.name.localizedCaseInsensitiveContains(searchText) ||
                (circle.description ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(categories, id: \.0) { category in
                        CategoryChip(
                            title: category.1,
                            icon: category.2,
                            isSelected: selectedCategory == category.0
                        ) {
                            selectedCategory = category.0
                        }
                    }
                }
                .padding()
            }
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search public circles...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: { showingMap.toggle() }) {
                    Image(systemName: showingMap ? "list.bullet" : "map")
                        .foregroundColor(circlesBlue)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            
            // Content
            if showingMap {
                DiscoverMapView(circles: filteredCircles)
            } else {
                ScrollView {
                    if isLoading {
                        ProgressView()
                            .padding()
                    } else if filteredCircles.isEmpty {
                        EmptyDiscoverView()
                            .padding()
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 15) {
                            ForEach(filteredCircles) { circle in
                                NavigationLink(destination: CircleDetailView(circle: circle)) {
                                    DiscoverCircleCard(circle: circle)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("Discover")
        .onAppear {
            fetchPublicCircles()
        }
        .refreshable {
            await fetchPublicCirclesAsync()
        }
    }
    
    private func fetchPublicCircles() {
        isLoading = true
        CircleService.shared.fetchPublicCircles { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let circles):
                    self.publicCircles = circles
                case .failure(let error):
                    print("Failed to fetch public circles: \(error)")
                }
                self.isLoading = false
            }
        }
    }
    
    private func fetchPublicCirclesAsync() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let circles = try await withCheckedThrowingContinuation { continuation in
                CircleService.shared.fetchPublicCircles { result in
                    switch result {
                    case .success(let circles):
                        continuation.resume(returning: circles)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            await MainActor.run {
                self.publicCircles = circles
                self.isLoading = false
            }
        } catch {
            print("Failed to fetch public circles: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

struct CategoryChip: View {
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

struct DiscoverCircleCard: View {
    let circle: Circle
    @State private var coverImage: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image
            ZStack {
                if let coverImage = coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
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
                    .frame(height: 120)
                    .overlay(
                        Image(systemName: categoryIcon(for: circle.category.rawValue))
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.8))
                    )
                }
                
                // Place count overlay
                VStack {
                    HStack {
                        Spacer()
                        Label("\(circle.places?.count ?? 0)", systemImage: "mappin.circle.fill")
                            .font(.caption)
                            .padding(5)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .padding(5)
                    }
                    Spacer()
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 5) {
                Text(circle.name)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                if let description = circle.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Owner info
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.caption2)
                    Text("Public Circle")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .padding(10)
        }
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
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

struct DiscoverMapView: View {
    let circles: [Circle]
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    var body: some View {
        // Map view disabled - location is stored as string, not coordinates
        Map(coordinateRegion: $region)
            .overlay(
                VStack {
                    Text("Map view coming soon")
                        .font(.headline)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(10)
                }
            )
        .onAppear {
            updateRegion()
        }
    }
    
    private var circlesWithLocations: [Circle] {
        circles.filter { $0.location != nil }
    }
    
    private func updateRegion() {
        // Map region update disabled - location is stored as string, not coordinates
    }
}

struct EmptyDiscoverView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Public Circles Found")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Check back later to discover circles shared by the community")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 50)
    }
}

#Preview {
    NavigationView {
        DiscoverView()
            .environmentObject(CircleManager.shared)
    }
}