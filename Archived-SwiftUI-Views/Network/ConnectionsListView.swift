import SwiftUI

struct ConnectionsListView: View {
    @StateObject private var networkManager = NetworkManager.shared
    let searchText: String
    
    private var filteredConnections: [Connection] {
        if searchText.isEmpty {
            return networkManager.connections
        }
        return networkManager.connections.filter { connection in
            connection.connectedUser?.displayName.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }
    
    private var pendingConnections: [Connection] {
        networkManager.pendingConnections
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Pending connections section
                if !pendingConnections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pending Connections")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(pendingConnections) { connection in
                            PendingConnectionRow(connection: connection)
                        }
                    }
                    .padding(.vertical)
                    
                    Divider()
                }
                
                // Active connections
                if filteredConnections.isEmpty && searchText.isEmpty && pendingConnections.isEmpty {
                    EmptyConnectionsView()
                } else if filteredConnections.isEmpty && !searchText.isEmpty {
                    NoSearchResultsView(searchText: searchText)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("My Connections (\(filteredConnections.count))")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(filteredConnections) { connection in
                            NavigationLink(destination: ConnectionDetailView(connection: connection)) {
                                ConnectionRow(connection: connection)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
    }
}

struct ConnectionRow: View {
    let connection: Connection
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            if let profilePicture = connection.connectedUser?.profilePicture,
               let url = URL(string: profilePicture) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                }
                .frame(width: 50, height: 50)
                .clipShape(SwiftUI.Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.connectedUser?.displayName ?? "Unknown User")
                    .font(.headline)
                
                HStack {
                    Image(systemName: "circle.grid.3x3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(connection.sharedCircleCount) shared circles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct PendingConnectionRow: View {
    let connection: Connection
    @StateObject private var networkManager = NetworkManager.shared
    @State private var isProcessing = false
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            if let profilePicture = connection.connectedUser?.profilePicture,
               let url = URL(string: profilePicture) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                }
                .frame(width: 50, height: 50)
                .clipShape(SwiftUI.Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.connectedUser?.displayName ?? "Unknown User")
                    .font(.headline)
                
                Text("Connection request")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                HStack(spacing: 8) {
                    Button(action: declineConnection) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    
                    Button(action: acceptConnection) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
    
    private func acceptConnection() {
        isProcessing = true
        networkManager.acceptConnection(connection.id) { result in
            isProcessing = false
            if case .failure(let error) = result {
                print("Failed to accept connection: \(error)")
            }
        }
    }
    
    private func declineConnection() {
        isProcessing = true
        networkManager.declineConnection(connection.id) { result in
            isProcessing = false
            if case .failure(let error) = result {
                print("Failed to decline connection: \(error)")
            }
        }
    }
}

struct EmptyConnectionsView: View {
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Connections Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Connect with other Circles users to share your favorite places")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            VStack(spacing: 16) {
                Text("How to add connections:")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.title2)
                        .foregroundColor(circlesBlue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tap the add connection button above")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Share your unique invite link via text, email, or social media to connect with friends")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 20)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct NoSearchResultsView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No results for \"\(searchText)\"")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}