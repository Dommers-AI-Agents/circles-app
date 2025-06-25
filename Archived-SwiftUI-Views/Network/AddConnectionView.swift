import SwiftUI

struct AddConnectionView: View {
    @Environment(\.dismiss) var dismiss
    private let networkManager = NetworkManager.shared
    @State private var searchText = ""
    @State private var searchResults: [User] = []
    @State private var isSearching = false
    @State private var selectedUser: User?
    @State private var connectionMessage = ""
    @State private var isSending = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search users by name or email...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            searchUsers()
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                
                if selectedUser != nil {
                    selectedUserView
                } else {
                    searchResultsView
                }
            }
            .navigationTitle("Add Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedUser != nil {
                        Button("Send") {
                            sendConnectionRequest()
                        }
                        .disabled(isSending)
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    @ViewBuilder
    private var searchResultsView: some View {
        if isSearching {
            ProgressView("Searching...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty && !searchText.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                
                Text("No users found")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Try searching with a different name or email")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if !searchResults.isEmpty {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(searchResults) { user in
                        UserSearchRow(user: user) {
                            selectedUser = user
                        }
                    }
                }
                .padding()
            }
        } else {
            VStack(spacing: 20) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                
                Text("Search for users")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Find other Circles users to connect and share circles")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
    
    @ViewBuilder
    private var selectedUserView: some View {
        VStack(spacing: 20) {
            // Selected user info
            VStack(spacing: 16) {
                if let profilePicture = selectedUser?.profilePicture,
                   let url = URL(string: profilePicture) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(_), .empty:
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.gray)
                        @unknown default:
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(SwiftUI.Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.gray)
                }
                
                VStack(spacing: 8) {
                    Text(selectedUser?.displayName ?? "")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text(selectedUser?.email ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let bio = selectedUser?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Message input
            VStack(alignment: .leading, spacing: 8) {
                Text("Add a message (optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("Hi! I'd like to connect with you on Circles...", text: $connectionMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
            
            // Change selection button
            Button(action: { selectedUser = nil }) {
                Text("Select Different User")
                    .foregroundColor(circlesBlue)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func searchUsers() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        UserService.shared.searchUsers(query: searchText) { result in
            isSearching = false
            switch result {
            case .success(let users):
                // Filter out already connected users and self
                searchResults = users.filter { user in
                    user.id != AuthManager.shared.currentUser?.id &&
                    !networkManager.connections.contains { $0.connectedUserId == user.id } &&
                    !networkManager.pendingConnections.contains { $0.connectedUserId == user.id }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func sendConnectionRequest() {
        guard let user = selectedUser else { return }
        
        isSending = true
        networkManager.sendConnectionRequest(to: user.id, message: connectionMessage.isEmpty ? nil : connectionMessage) { result in
            isSending = false
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

struct UserSearchRow: View {
    let user: User
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile picture
                if let profilePicture = user.profilePicture,
                   let url = URL(string: profilePicture) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(_), .empty:
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        @unknown default:
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(SwiftUI.Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(user.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let location = user.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                            Text(location)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}