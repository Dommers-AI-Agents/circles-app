import SwiftUI

struct MyNetworkView: View {
    @StateObject private var networkManager = NetworkManager.shared
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var showingAddConnection = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search connections or circles...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)
                
                // Segmented Control
                Picker("View", selection: $selectedTab) {
                    Text("Connections").tag(0)
                    Text("Shared Circles").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color(.systemGray6))
            
            // Content
            if networkManager.isLoading {
                ProgressView("Loading network...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if selectedTab == 0 {
                    ConnectionsListView(searchText: searchText)
                } else {
                    SharedCirclesListView(searchText: searchText)
                }
            }
        }
        .navigationTitle("My Network")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingAddConnection) {
            AddConnectionView()
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
        .onAppear {
            networkManager.loadNetworkData()
        }
    }
}

// Preview
#Preview {
    NavigationView {
        MyNetworkView()
    }
    .environmentObject(NetworkManager.shared)
}