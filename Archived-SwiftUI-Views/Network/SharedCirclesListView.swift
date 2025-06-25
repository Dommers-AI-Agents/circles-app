import SwiftUI

struct SharedCirclesListView: View {
    private let networkManager = NetworkManager.shared
    private let circleManager = CircleManager.shared
    let searchText: String
    
    private var sharedCircles: [Circle] {
        let circlesWithShares = circleManager.circles.filter { circle in
            circle.hasActiveShares || networkManager.getSharesForCircle(circle.id).count > 0
        }
        
        if searchText.isEmpty {
            return circlesWithShares
        }
        
        return circlesWithShares.filter { circle in
            circle.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        ScrollView {
            if sharedCircles.isEmpty && searchText.isEmpty {
                EmptySharedCirclesView()
            } else if sharedCircles.isEmpty && !searchText.isEmpty {
                NoSearchResultsView(searchText: searchText)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(sharedCircles) { circle in
                        NavigationLink(destination: SharedCircleDetailView(circle: circle)) {
                            SharedCircleRow(circle: circle)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical)
            }
        }
    }
}

struct SharedCircleRow: View {
    let circle: Circle
    private let networkManager = NetworkManager.shared
    
    private var shareCount: Int {
        networkManager.getSharesForCircle(circle.id).count
    }
    
    private var shareTypeSummary: String {
        let shares = networkManager.getSharesForCircle(circle.id)
        let userShares = shares.filter { $0.shareType == .registeredUser }.count
        let emailShares = shares.filter { $0.shareType == .email }.count
        let linkShares = shares.filter { $0.shareType == .link }.count
        
        var summary: [String] = []
        if userShares > 0 { summary.append("\(userShares) users") }
        if emailShares > 0 { summary.append("\(emailShares) emails") }
        if linkShares > 0 { summary.append("\(linkShares) links") }
        
        return summary.joined(separator: ", ")
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Circle image or icon
            if let coverImage = circle.coverImage,
               let url = URL(string: coverImage) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_), .empty:
                        CircleCategoryIcon(category: circle.category)
                    @unknown default:
                        CircleCategoryIcon(category: circle.category)
                    }
                }
                .frame(width: 60, height: 60)
                .cornerRadius(10)
            } else {
                CircleCategoryIcon(category: circle.category)
                    .frame(width: 60, height: 60)
                    .background(Color(.systemGray5))
                    .cornerRadius(10)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(circle.name)
                    .font(.headline)
                
                Text("Shared with \(shareCount) \(shareCount == 1 ? "person" : "people")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if !shareTypeSummary.isEmpty {
                    Text(shareTypeSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Privacy indicator
                PrivacyBadge(privacy: circle.privacy)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct CircleCategoryIcon: View {
    let category: CircleCategory
    
    var iconName: String {
        switch category {
        case .travel: return "airplane.departure"
        case .food: return "fork.knife.circle.fill"
        case .services: return "wrench.and.screwdriver.fill"
        case .shopping: return "bag.fill"
        case .healthcare: return "heart.text.square.fill"
        case .entertainment: return "music.note.tv.fill"
        case .other: return "square.stack.3d.up.fill"
        }
    }
    
    var body: some View {
        Image(systemName: iconName)
            .font(.title2)
            .foregroundColor(.blue)
    }
}

struct PrivacyBadge: View {
    let privacy: PrivacyLevel
    
    var iconName: String {
        switch privacy {
        case .public: return "globe"
        case .friends: return "person.2"
        case .private: return "lock"
        }
    }
    
    var body: some View {
        Image(systemName: iconName)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(4)
            .background(Color(.systemGray5))
            .cornerRadius(4)
    }
}

struct EmptySharedCirclesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Shared Circles")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Share your circles with connections to collaborate on favorite places")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}