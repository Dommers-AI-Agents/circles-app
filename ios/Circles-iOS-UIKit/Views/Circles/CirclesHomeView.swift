import SwiftUI

struct CirclesHomeView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var circleManager: CircleManager
    @State private var showingCreateCircle = false
    @State private var searchText = ""
    
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
                    Text(circle.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
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
    
    private func privacyIcon(for privacy: String) -> String {
        switch privacy.lowercased() {
        case "public": return "globe"
        case "friends": return "person.2"
        case "private": return "lock"
        default: return "questionmark.circle"
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