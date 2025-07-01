import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) var dismiss
    
    @State private var displayName: String = ""
    @State private var bio: String = ""
    @State private var location: String = ""
    @State private var selectedImage: UIImage?
    @State private var currentImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingImageOptions = false
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        NavigationView {
            Form {
                // Profile Image Section
                Section {
                    VStack {
                        ZStack {
                            if let image = selectedImage ?? currentImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 120)
                                    .clipShape(SwiftUI.Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 120))
                                    .foregroundColor(.gray)
                            }
                        }
                        .overlay(
                            SwiftUI.Circle()
                                .stroke(circlesBlue, lineWidth: 3)
                        )
                        .onTapGesture {
                            showingImageOptions = true
                        }
                        
                        Button("Change Photo") {
                            showingImageOptions = true
                        }
                        .font(.caption)
                        .foregroundColor(circlesBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                
                // Basic Info Section
                Section(header: Text("Basic Information")) {
                    VStack(alignment: .leading) {
                        Text("Display Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter your display name", text: $displayName)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Location (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("City, State", text: $location)
                    }
                }
                
                // Bio Section
                Section(header: Text("About")) {
                    VStack(alignment: .leading) {
                        Text("Bio (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $bio)
                            .frame(minHeight: 100)
                    }
                }
                
                // Account Info (Read-only)
                Section(header: Text("Account Information")) {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(authManager.currentUser?.email ?? "")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Member Since")
                        Spacer()
                        Text(authManager.currentUser?.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        updateProfile()
                    }
                    .disabled(displayName.isEmpty || isLoading || !hasChanges)
                }
            }
        }
        .onAppear {
            loadCurrentUserData()
        }
        .confirmationDialog("Choose Image Source", isPresented: $showingImageOptions) {
            Button("Take Photo") {
                // TODO: Implement camera
            }
            Button("Choose from Library") {
                showingImagePicker = true
            }
            if selectedImage != nil || currentImage != nil {
                Button("Remove Photo", role: .destructive) {
                    selectedImage = nil
                    currentImage = nil
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .overlay(
            Group {
                if isLoading {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView("Updating Profile...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        )
    }
    
    private var hasChanges: Bool {
        guard let currentUser = authManager.currentUser else { return false }
        
        return displayName != currentUser.displayName ||
               bio != (currentUser.bio ?? "") ||
               location != (currentUser.location ?? "") ||
               selectedImage != nil
    }
    
    private func loadCurrentUserData() {
        guard let currentUser = authManager.currentUser else { return }
        
        displayName = currentUser.displayName
        bio = currentUser.bio ?? ""
        location = currentUser.location ?? ""
        
        // Load profile image
        if let urlString = currentUser.profilePicture,
           let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.currentImage = image
                    }
                }
            }.resume()
        }
    }
    
    private func updateProfile() {
        guard !displayName.isEmpty else { return }
        
        isLoading = true
        
        Task {
            do {
                try await userManager.updateProfile(
                    displayName: displayName,
                    bio: bio.isEmpty ? nil : bio,
                    location: location.isEmpty ? nil : location,
                    profileImage: selectedImage
                )
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    EditProfileView()
        .environmentObject(AuthManager.shared)
        .environmentObject(UserManager.shared)
}