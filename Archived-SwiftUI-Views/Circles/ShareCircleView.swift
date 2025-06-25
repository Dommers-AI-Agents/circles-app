import SwiftUI
import MessageUI

struct ShareCircleView: View {
    let circle: Circle
    @Environment(\.dismiss) var dismiss
    @StateObject private var networkManager = NetworkManager.shared
    @State private var selectedContact: User?
    @State private var phoneNumber = ""
    @State private var shareLink: String?
    @State private var isGeneratingLink = false
    @State private var showingMessageCompose = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var searchText = ""
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var filteredConnections: [Connection] {
        if searchText.isEmpty {
            return networkManager.connections
        }
        return networkManager.connections.filter { connection in
            connection.connectedUser?.displayName.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Share options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Share \"\(circle.name)\"")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    // Share with connections
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Share with Connections")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if networkManager.connections.isEmpty {
                            HStack {
                                Image(systemName: "person.2.slash")
                                    .foregroundColor(.secondary)
                                Text("No connections yet")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        } else {
                            // Search bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Search connections...", text: $searchText)
                            }
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .padding(.horizontal)
                            
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(filteredConnections) { connection in
                                        ShareConnectionRow(
                                            connection: connection,
                                            isSelected: selectedContact?.id == connection.connectedUser?.id,
                                            onTap: {
                                                selectedContact = connection.connectedUser
                                                shareWithConnection(connection)
                                            }
                                        )
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical)
                    
                    // Share via SMS
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Share via SMS")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        HStack {
                            TextField("Phone number", text: $phoneNumber)
                                .keyboardType(.phonePad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button(action: shareViaSMS) {
                                if isGeneratingLink {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Send")
                                        .fontWeight(.medium)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(circlesBlue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .disabled(phoneNumber.isEmpty || isGeneratingLink)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
                .padding(.top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingMessageCompose) {
                MessageComposeView(
                    recipients: [phoneNumber],
                    body: createShareMessage(),
                    onResult: handleMessageResult
                )
            }
        }
    }
    
    private func shareWithConnection(_ connection: Connection) {
        isGeneratingLink = true
        
        // Share circle with the connection
        networkManager.shareCircle(
            circle.id,
            with: connection.connectedUserId,
            accessLevel: .canAddPlaces
        ) { result in
            isGeneratingLink = false
            
            switch result {
            case .success(let share):
                // Show success message
                dismiss()
                // Note: In a real app, you might want to show a success message
                // or navigate to a share details view
                
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func shareViaSMS() {
        guard !phoneNumber.isEmpty else { return }
        
        isGeneratingLink = true
        
        // Create a public share link
        networkManager.shareCircle(
            circle.id,
            with: nil,
            accessLevel: .viewOnly,
            expiresIn: 7 // 7 days
        ) { result in
            isGeneratingLink = false
            
            switch result {
            case .success(let share):
                shareLink = createDeepLink(shareId: share.id)
                
                if MFMessageComposeViewController.canSendText() {
                    showingMessageCompose = true
                } else {
                    // Fallback: Copy to clipboard
                    UIPasteboard.general.string = createShareMessage()
                    errorMessage = "SMS not available. Message copied to clipboard."
                    showingError = true
                }
                
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func createDeepLink(shareId: String) -> String {
        // Deep link format: circles://share/circle/{shareId}
        return "circles://share/circle/\(shareId)"
    }
    
    private func createShareMessage() -> String {
        let appStoreLink = "https://apps.apple.com/app/circles/id123456789" // Replace with actual App Store ID
        
        if let shareLink = shareLink {
            return """
            I'd like to share my "\(circle.name)" circle with you on Circles!
            
            \(circle.description ?? "")
            
            Click here to view: \(shareLink)
            
            Don't have Circles? Download it here: \(appStoreLink)
            """
        } else {
            return """
            I'd like to share my "\(circle.name)" circle with you on Circles!
            
            Download the app to view: \(appStoreLink)
            """
        }
    }
    
    private func handleMessageResult(_ result: MessageComposeResult) {
        switch result {
        case .sent:
            dismiss()
        case .cancelled:
            break
        case .failed:
            errorMessage = "Failed to send message"
            showingError = true
        @unknown default:
            break
        }
    }
}

struct ShareConnectionRow: View {
    let connection: Connection
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Avatar
                SwiftUI.Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(connection.connectedUser?.displayName.prefix(1).uppercased() ?? "?")
                            .font(.headline)
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.connectedUser?.displayName ?? "Unknown")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if connection.sharedCircleCount > 0 {
                        Text("\(connection.sharedCircleCount) shared circles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Message Compose View for SMS
struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onResult: (MessageComposeResult) -> Void
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }
    
    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onResult: (MessageComposeResult) -> Void
        
        init(onResult: @escaping (MessageComposeResult) -> Void) {
            self.onResult = onResult
        }
        
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
            onResult(result)
        }
    }
}

#Preview {
    ShareCircleView(circle: Circle(
        id: "1",
        name: "Best Coffee Shops",
        description: "My favorite coffee spots in the city",
        coverImage: nil,
        owner: "user1",
        ownerDetails: nil,
        places: ["place1", "place2"],
        placesWithDetails: nil,
        privacy: .private,
        category: .food,
        location: "San Francisco",
        tags: ["coffee", "cafe"],
        sharedWith: nil,
        followers: nil,
        activeShares: nil,
        shareSettings: nil,
        isSharedWithMe: false,
        sharedBy: nil,
        myAccessLevel: nil,
        createdAt: Date(),
        updatedAt: Date()
    ))
}