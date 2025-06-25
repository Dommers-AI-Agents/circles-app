import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var updateChecker = UpdateChecker()
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                CirclesHomeView()
            }
            .tabItem {
                Label("Circles", systemImage: "circle.grid.3x3.fill")
            }
            .tag(0)
            
            NavigationView {
                MyNetworkView()
            }
            .tabItem {
                Label("My Network", systemImage: "person.2.circle.fill")
            }
            .tag(1)
            
            NavigationView {
                DiscoverView()
            }
            .tabItem {
                Label("Discover", systemImage: "magnifyingglass")
            }
            .tag(2)
            
            NavigationView {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.circle.fill")
            }
            .tag(3)
        }
        .accentColor(circlesBlue)
        .onAppear {
            updateChecker.checkForUpdates()
        }
        .alert("Update Available", isPresented: $updateChecker.updateAvailable) {
            Button("Update") {
                if let url = URL(string: "https://apps.apple.com/app/id\(Bundle.main.bundleIdentifier ?? "")") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text(updateChecker.updateMessage)
        }
    }
}

// Update checker is now in Services/UpdateChecker.swift

#Preview {
    MainTabView()
}