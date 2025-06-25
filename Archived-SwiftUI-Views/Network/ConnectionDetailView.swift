import SwiftUI

struct ConnectionDetailView: View {
    let connection: Connection
    @StateObject private var networkManager = NetworkManager.shared
    @StateObject private var circleManager = CircleManager.shared
    @State private var sharedCircles: [Circle] = []
    @State private var isLoading = true
    @State private var showingShareSheet = false
    @State private var showingConfirmBlock = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile section
                profileSection
                
                // Actions
                actionButtons
                
                // Shared circles section
                sharedCirclesSection
            }
            .padding()
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShareSheet) {
            ShareCircleWithConnectionView(connection: connection)
        }
        .alert("Block Connection", isPresented: $showingConfirmBlock) {
            Button("Cancel", role: .cancel) { }
            Button("Block", role: .destructive) {
                blockConnection()
            }
        } message: {
            Text("Are you sure you want to block \(connection.connectedUser?.displayName ?? "this user")? They will no longer have access to your shared circles.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadSharedCircles()
        }
    }
    
    @ViewBuilder
    private var profileSection: some View {
        VStack(spacing: 16) {
            // Profile picture
            if let profilePicture = connection.connectedUser?.profilePicture,
               let url = URL(string: profilePicture) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.gray)
                }
                .frame(width: 100, height: 100)
                .clipShape(SwiftUI.Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.gray)
            }
            
            VStack(spacing: 8) {
                Text(connection.connectedUser?.displayName ?? "Unknown User")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let email = connection.connectedUser?.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let bio = connection.connectedUser?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                
                HStack {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    if let acceptedAt = connection.acceptedAt {
                        Text("• \(acceptedAt, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: { showingShareSheet = true }) {
                Label("Share Circle", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(circlesBlue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Button(action: { showingConfirmBlock = true }) {
                Label("Block", systemImage: "hand.raised.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(10)
            }
        }
    }
    
    @ViewBuilder
    private var sharedCirclesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shared Circles")
                    .font(.headline)
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("\(sharedCircles.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if sharedCircles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    
                    Text("No circles shared yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: { showingShareSheet = true }) {
                        Text("Share your first circle")
                            .font(.subheadline)
                            .foregroundColor(circlesBlue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(sharedCircles) { circle in
                        SharedCircleWithConnectionRow(
                            circle: circle,
                            connection: connection,
                            onUnshare: { unshareCircle(circle) }
                        )
                    }
                }
            }
        }
    }
    
    private func loadSharedCircles() {
        isLoading = true
        networkManager.getSharedCirclesWithConnection(connection.id) { result in
            isLoading = false
            switch result {
            case .success(let circles):
                sharedCircles = circles
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func blockConnection() {
        networkManager.blockConnection(connection.id) { result in
            switch result {
            case .success:
                // Navigate back
                break
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func unshareCircle(_ circle: Circle) {
        // Find the share for this circle and connection
        if let share = networkManager.sharedCircles.first(where: {
            $0.circleId == circle.id && $0.sharedWith == connection.connectedUserId
        }) {
            networkManager.revokeShare(share.id, circleId: circle.id) { result in
                switch result {
                case .success:
                    sharedCircles.removeAll { $0.id == circle.id }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

struct SharedCircleWithConnectionRow: View {
    let circle: Circle
    let connection: Connection
    let onUnshare: () -> Void
    @State private var showingConfirmUnshare = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Circle icon
            if let coverImage = circle.coverImage,
               let url = URL(string: coverImage) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    CircleCategoryIcon(category: circle.category)
                }
                .frame(width: 50, height: 50)
                .cornerRadius(8)
            } else {
                CircleCategoryIcon(category: circle.category)
                    .frame(width: 50, height: 50)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(circle.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption2)
                    Text("\(circle.places?.count ?? 0) places")
                        .font(.caption)
                    
                    Text("•")
                    
                    PrivacyBadge(privacy: circle.privacy)
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { showingConfirmUnshare = true }) {
                Text("Unshare")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .confirmationDialog(
            "Unshare Circle",
            isPresented: $showingConfirmUnshare,
            titleVisibility: .visible
        ) {
            Button("Unshare", role: .destructive) {
                onUnshare()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(connection.connectedUser?.displayName ?? "This user") will no longer have access to \(circle.name)")
        }
    }
}