import SwiftUI

struct ShareCircleWithConnectionView: View {
    let connection: Connection
    @Environment(\.dismiss) var dismiss
    private let circleManager = CircleManager.shared
    private let networkManager = NetworkManager.shared
    @State private var selectedCircles: Set<String> = []
    @State private var accessLevel: AccessLevel = .viewOnly
    @State private var expiresIn: Int? = nil
    @State private var isSharing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    private var availableCircles: [Circle] {
        circleManager.circles.filter { circle in
            !networkManager.isCircleSharedWith(circleId: circle.id, userId: connection.connectedUserId)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Connection info
                connectionHeader
                
                if availableCircles.isEmpty {
                    noCirclesView
                } else {
                    Form {
                        circleSelectionSection
                        accessSettingsSection
                        expirationSection
                    }
                }
            }
            .navigationTitle("Share Circles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Share") {
                        shareCircles()
                    }
                    .disabled(selectedCircles.isEmpty || isSharing)
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
    private var connectionHeader: some View {
        HStack(spacing: 12) {
            if let profilePicture = connection.connectedUser?.profilePicture,
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
                Text("Share with")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(connection.connectedUser?.displayName ?? "Unknown User")
                    .font(.headline)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    @ViewBuilder
    private var noCirclesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("All circles already shared")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("You've already shared all your circles with \(connection.connectedUser?.displayName ?? "this user")")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    @ViewBuilder
    private var circleSelectionSection: some View {
        Section(header: Text("Select Circles to Share")) {
            ForEach(availableCircles) { circle in
                CircleSelectionRow(
                    circle: circle,
                    isSelected: selectedCircles.contains(circle.id),
                    onToggle: {
                        if selectedCircles.contains(circle.id) {
                            selectedCircles.remove(circle.id)
                        } else {
                            selectedCircles.insert(circle.id)
                        }
                    }
                )
            }
            
            if !selectedCircles.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("\(selectedCircles.count) circle\(selectedCircles.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var accessSettingsSection: some View {
        Section(header: Text("Access Permissions")) {
            Picker("Access Level", selection: $accessLevel) {
                ForEach([AccessLevel.viewOnly, .canAddPlaces], id: \.self) { level in
                    VStack(alignment: .leading) {
                        Text(level.displayName)
                        Text(level.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .tag(level)
                }
            }
            .pickerStyle(DefaultPickerStyle())
        }
    }
    
    @ViewBuilder
    private var expirationSection: some View {
        Section(header: Text("Expiration (Optional)")) {
            Picker("Expires", selection: $expiresIn) {
                Text("Never").tag(nil as Int?)
                Text("1 Day").tag(1 as Int?)
                Text("7 Days").tag(7 as Int?)
                Text("30 Days").tag(30 as Int?)
                Text("90 Days").tag(90 as Int?)
            }
            .pickerStyle(DefaultPickerStyle())
        }
    }
    
    private func shareCircles() {
        isSharing = true
        var shareCount = 0
        var errorCount = 0
        
        for circleId in selectedCircles {
            networkManager.shareCircle(
                circleId,
                with: connection.connectedUserId,
                accessLevel: accessLevel,
                expiresIn: expiresIn
            ) { result in
                switch result {
                case .success:
                    shareCount += 1
                case .failure:
                    errorCount += 1
                }
                
                // Check if all shares are complete
                if shareCount + errorCount == selectedCircles.count {
                    isSharing = false
                    if errorCount > 0 {
                        errorMessage = "Failed to share \(errorCount) circle\(errorCount == 1 ? "" : "s")"
                        showingError = true
                    } else {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CircleSelectionRow: View {
    let circle: Circle
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title3)
                
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
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                } else {
                    CircleCategoryIcon(category: circle.category)
                        .frame(width: 40, height: 40)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(circle.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Label("\(circle.places?.count ?? 0) places", systemImage: "mappin")
                            .font(.caption)
                        
                        PrivacyBadge(privacy: circle.privacy)
                    }
                    .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}