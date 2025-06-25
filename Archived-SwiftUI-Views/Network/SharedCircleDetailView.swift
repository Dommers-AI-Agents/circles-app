import SwiftUI

struct SharedCircleDetailView: View {
    let circle: Circle
    @StateObject private var networkManager = NetworkManager.shared
    @State private var circleShares: [CircleShare] = []
    @State private var isLoading = true
    @State private var showingShareOptions = false
    @State private var selectedShare: CircleShare?
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    private var activeShares: [CircleShare] {
        circleShares.filter { !$0.isExpired }
    }
    
    private var expiredShares: [CircleShare] {
        circleShares.filter { $0.isExpired }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Circle info section
                circleInfoSection
                
                // Share summary
                shareSummarySection
                
                // Active shares
                if !activeShares.isEmpty {
                    activeSharesSection
                }
                
                // Expired shares
                if !expiredShares.isEmpty {
                    expiredSharesSection
                }
            }
            .padding()
        }
        .navigationTitle("Share Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingShareOptions = true }) {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingShareOptions) {
            ShareCircleView(circle: circle)
                .onDisappear {
                    loadCircleShares()
                }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadCircleShares()
        }
    }
    
    @ViewBuilder
    private var circleInfoSection: some View {
        HStack(spacing: 16) {
            // Circle image
            if let coverImage = circle.coverImage,
               let url = URL(string: coverImage) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    CircleCategoryIcon(category: circle.category)
                        .font(.title)
                }
                .frame(width: 80, height: 80)
                .cornerRadius(12)
            } else {
                CircleCategoryIcon(category: circle.category)
                    .font(.title)
                    .frame(width: 80, height: 80)
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(circle.name)
                    .font(.title3)
                    .fontWeight(.bold)
                
                HStack(spacing: 12) {
                    Label("\(circle.places?.count ?? 0) places", systemImage: "mappin.circle.fill")
                        .font(.caption)
                    
                    PrivacyBadge(privacy: circle.privacy)
                }
                .foregroundColor(.secondary)
                
                if let description = circle.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var shareSummarySection: some View {
        HStack(spacing: 20) {
            ShareStatView(
                title: "Active",
                count: activeShares.count,
                icon: "person.2.fill",
                color: .green
            )
            
            ShareStatView(
                title: "Total",
                count: circleShares.count,
                icon: "square.and.arrow.up.fill",
                color: circlesBlue
            )
            
            ShareStatView(
                title: "Expired",
                count: expiredShares.count,
                icon: "clock.fill",
                color: .orange
            )
        }
    }
    
    @ViewBuilder
    private var activeSharesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Shares")
                .font(.headline)
            
            LazyVStack(spacing: 8) {
                ForEach(activeShares) { share in
                    ShareRow(
                        share: share,
                        onRevoke: { revokeShare(share) },
                        onTap: { selectedShare = share }
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private var expiredSharesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Expired Shares")
                .font(.headline)
                .foregroundColor(.secondary)
            
            LazyVStack(spacing: 8) {
                ForEach(expiredShares) { share in
                    ShareRow(
                        share: share,
                        isExpired: true,
                        onRevoke: { revokeShare(share) },
                        onTap: { selectedShare = share }
                    )
                }
            }
        }
    }
    
    private func loadCircleShares() {
        isLoading = true
        networkManager.getCircleShares(for: circle.id) { result in
            isLoading = false
            switch result {
            case .success(let shares):
                circleShares = shares
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func revokeShare(_ share: CircleShare) {
        networkManager.revokeShare(share.id, circleId: circle.id) { result in
            switch result {
            case .success:
                circleShares.removeAll { $0.id == share.id }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

struct ShareStatView: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct ShareRow: View {
    let share: CircleShare
    var isExpired: Bool = false
    let onRevoke: () -> Void
    let onTap: () -> Void
    @State private var showingRevokeConfirm = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Share type icon
                Image(systemName: share.shareType.icon)
                    .font(.title3)
                    .foregroundColor(isExpired ? .gray : shareTypeColor)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(share.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isExpired ? .secondary : .primary)
                    
                    HStack(spacing: 8) {
                        Text(share.accessLevel.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                        
                        if share.hasBeenAccessed {
                            Label("Accessed", systemImage: "eye.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        
                        if isExpired {
                            Label("Expired", systemImage: "clock.badge.xmark")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        } else if let expiresAt = share.expiresAt {
                            Text(expiresAt, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if !isExpired {
                    Button(action: { showingRevokeConfirm = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog(
            "Revoke Access",
            isPresented: $showingRevokeConfirm,
            titleVisibility: .visible
        ) {
            Button("Revoke Access", role: .destructive) {
                onRevoke()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(share.displayName) will immediately lose access to this circle")
        }
    }
    
    private var shareTypeColor: Color {
        switch share.shareType {
        case .registeredUser: return .blue
        case .email: return .orange
        case .link: return .purple
        }
    }
}