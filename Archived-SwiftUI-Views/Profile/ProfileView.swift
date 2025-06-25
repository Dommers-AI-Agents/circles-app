import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var circleManager: CircleManager
    @State private var showingEditProfile = false
    @State private var showingSettings = false
    @State private var profileImage: UIImage?
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var user: User? {
        authManager.currentUser
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile header
                VStack(spacing: 15) {
                    // Profile image
                    ZStack {
                        if let profileImage = profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(SwiftUI.Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 100))
                                .foregroundColor(.gray)
                        }
                    }
                    .overlay(
                        SwiftUI.Circle()
                            .stroke(circlesBlue, lineWidth: 3)
                    )
                    
                    // Name and email
                    VStack(spacing: 5) {
                        Text(user?.displayName ?? "User")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(user?.email ?? "")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Location and bio
                    if let location = user?.location, !location.isEmpty {
                        Label(location, systemImage: "location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let bio = user?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Stats
                    HStack(spacing: 40) {
                        VStack {
                            Text("\(circleManager.circles.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Circles")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(userManager.friends.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Friends")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(totalPlaces)")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Places")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical)
                }
                .padding()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: { showingEditProfile = true }) {
                        HStack {
                            Image(systemName: "person.fill")
                            Text("Edit Profile")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(circlesBlue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    Button(action: { showingSettings = true }) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                            Text("Settings")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    
                    Button(action: logout) {
                        HStack {
                            Image(systemName: "arrow.right.square.fill")
                            Text("Log Out")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                // App version
                let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
                
                // Friend requests
                if !userManager.friendRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Friend Requests")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(userManager.friendRequests) { request in
                            FriendRequestRow(user: request.from)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                }
            }
        }
        .navigationTitle("Profile")
        .onAppear {
            loadProfileData()
        }
        .refreshable {
            await refreshProfile()
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environmentObject(authManager)
                .environmentObject(userManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(authManager)
        }
    }
    
    private var totalPlaces: Int {
        circleManager.circles.reduce(0) { $0 + ($1.places?.count ?? 0) }
    }
    
    private func loadProfileData() {
        // Load profile image
        if let urlString = user?.profilePicture,
           let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.profileImage = image
                    }
                }
            }.resume()
        }
        
        // Load friends and friend requests
        Task {
            await userManager.fetchFriends()
            await userManager.fetchFriendRequests()
        }
    }
    
    private func refreshProfile() async {
        // Refresh user data
        if let userId = authManager.currentUser?.id {
            do {
                let user = try await userManager.fetchUser(userId: userId)
                await MainActor.run {
                    authManager.currentUser = user
                }
            } catch {
                print("Failed to refresh profile: \(error)")
            }
        }
        
        // Refresh friends and circles
        await userManager.fetchFriends()
        await userManager.fetchFriendRequests()
        await circleManager.fetchCircles()
    }
    
    private func logout() {
        authManager.logout()
    }
}

struct FriendRequestRow: View {
    let user: User
    @EnvironmentObject var userManager: UserManager
    @State private var isProcessing = false
    
    var body: some View {
        HStack {
            // Profile image
            Image(systemName: "person.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.gray)
            
            VStack(alignment: .leading) {
                Text(user.displayName)
                    .font(.headline)
                if let location = user.location {
                    Text(location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                HStack(spacing: 10) {
                    Button(action: acceptRequest) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.green)
                            .clipShape(SwiftUI.Circle())
                    }
                    
                    Button(action: rejectRequest) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.red)
                            .clipShape(SwiftUI.Circle())
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private func acceptRequest() {
        isProcessing = true
        Task {
            do {
                try await userManager.acceptFriendRequest(from: user.id)
            } catch {
                print("Failed to accept friend request: \(error)")
            }
            await MainActor.run {
                isProcessing = false
            }
        }
    }
    
    private func rejectRequest() {
        isProcessing = true
        Task {
            do {
                try await userManager.rejectFriendRequest(from: user.id)
            } catch {
                print("Failed to reject friend request: \(error)")
            }
            await MainActor.run {
                isProcessing = false
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        NavigationView {
            List {
                Section("Account") {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(authManager.currentUser?.email ?? "")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Member Since")
                        Spacer()
                        Text(authManager.currentUser?.createdAt.formatted(date: .abbreviated, time: .omitted) ?? "")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Privacy") {
                    NavigationLink(destination: Text("Privacy Settings")) {
                        Text("Privacy Settings")
                    }
                    
                    NavigationLink(destination: Text("Blocked Users")) {
                        Text("Blocked Users")
                    }
                }
                
                Section("About") {
                    Link("Privacy Policy", destination: URL(string: "https://circles.app/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://circles.app/terms")!)
                    Link("Delete My Data", destination: URL(string: "https://circles.app/delete-data")!)
                }
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        ProfileView()
            .environmentObject(AuthManager.shared)
            .environmentObject(UserManager.shared)
            .environmentObject(CircleManager.shared)
    }
}