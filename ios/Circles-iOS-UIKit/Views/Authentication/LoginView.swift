import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showingEmailLogin = false
    @State private var showingRegistration = false
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [circlesBlue, circlesBlue.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo and welcome text
                VStack(spacing: 20) {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    Text("Circles")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Save and share your favorite places")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.bottom, 60)
                
                // Social login buttons
                VStack(spacing: 16) {
                    // Apple Sign In
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            handleAppleSignIn(result)
                        }
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(25)
                    
                    // Google Sign In
                    Button(action: googleSignIn) {
                        HStack {
                            Image("google_logo") // Add Google logo to assets
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text("Continue with Google")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(25)
                    }
                    
                    // Facebook Sign In
                    Button(action: facebookSignIn) {
                        HStack {
                            Image(systemName: "f.square.fill")
                                .font(.system(size: 20))
                            Text("Continue with Facebook")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(red: 24/255, green: 119/255, blue: 242/255))
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                    
                    // LinkedIn Sign In
                    Button(action: linkedInSignIn) {
                        HStack {
                            Image(systemName: "person.2.square.stack.fill")
                                .font(.system(size: 20))
                            Text("Continue with LinkedIn")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(red: 0/255, green: 119/255, blue: 181/255))
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(height: 1)
                        Text("OR")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 10)
                    
                    // Email login button
                    Button(action: { showingEmailLogin = true }) {
                        Text("Log in with Email")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.white.opacity(0.2))
                            .foregroundColor(.white)
                            .cornerRadius(25)
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Sign up link
                HStack {
                    Text("Don't have an account?")
                        .foregroundColor(.white.opacity(0.8))
                    Button("Sign Up") {
                        showingRegistration = true
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 17, weight: .bold))
                }
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showingEmailLogin) {
            EmailLoginView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showingRegistration) {
            RegistrationView()
                .environmentObject(authManager)
        }
        .overlay(
            Group {
                if authManager.isLoading {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
        )
    }
    
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let appleIDCredential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            
            let identityToken = appleIDCredential.identityToken
            let tokenString = identityToken.flatMap { String(data: $0, encoding: .utf8) }
            
            guard let token = tokenString else { return }
            
            let fullName = [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            
            Task {
                do {
                    try await authManager.loginWithSocial(
                        provider: "apple",
                        token: token,
                        name: fullName.isEmpty ? nil : fullName,
                        email: appleIDCredential.email
                    )
                } catch {
                    print("Apple Sign In failed: \(error)")
                }
            }
        case .failure(let error):
            print("Apple Sign In failed: \(error)")
        }
    }
    
    private func googleSignIn() {
        guard let presentingViewController = UIApplication.shared.windows.first?.rootViewController else { return }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            if let error = error {
                print("Google Sign In error: \(error)")
                return
            }
            
            guard let result = result,
                  let idToken = result.user.idToken?.tokenString else { return }
            
            Task {
                do {
                    try await authManager.loginWithSocial(
                        provider: "google",
                        token: idToken,
                        name: result.user.profile?.name,
                        email: result.user.profile?.email
                    )
                } catch {
                    print("Google Sign In failed: \(error)")
                }
            }
        }
    }
    
    private func facebookSignIn() {
        guard let presentingViewController = UIApplication.shared.windows.first?.rootViewController else { return }
        
        SocialAuthService.shared.signInWithFacebook(from: presentingViewController) { result in
            switch result {
            case .success(let user):
                // Facebook sign-in succeeded, user is already logged in via backend
                print("Facebook Sign In succeeded: \(user.displayName)")
            case .failure(let error):
                print("Facebook Sign In failed: \(error)")
            }
        }
    }
    
    private func linkedInSignIn() {
        guard let presentingViewController = UIApplication.shared.windows.first?.rootViewController else { return }
        
        SocialAuthService.shared.signInWithLinkedIn(from: presentingViewController) { result in
            switch result {
            case .success(let user):
                // LinkedIn sign-in succeeded, user is already logged in via backend
                print("LinkedIn Sign In succeeded: \(user.displayName)")
            case .failure(let error):
                print("LinkedIn Sign In failed: \(error)")
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager.shared)
}