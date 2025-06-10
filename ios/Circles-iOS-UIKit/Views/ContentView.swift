import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showSplash = true
    
    var body: some View {
        Group {
            if showSplash {
                SplashView()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                showSplash = false
                            }
                        }
                    }
            } else if authManager.isAuthenticated {
                MainTabView()
            } else {
                NavigationView {
                    LoginView()
                }
            }
        }
        .onAppear {
            authManager.checkAuthenticationStatus()
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
                .ignoresSafeArea()
            
            VStack {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                
                Text("Circles")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager.shared)
}