import SwiftUI

struct EmailLoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var rememberEmail = true
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    @AppStorage("savedEmail") private var savedEmail = ""
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [circlesBlue, circlesBlue.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Logo
                    VStack(spacing: 15) {
                        Image(systemName: "circle.grid.3x3.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text("Welcome Back")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.top, 40)
                    
                    // Form
                    VStack(spacing: 20) {
                        // Email field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            
                            TextField("Enter your email", text: $email)
                                .textFieldStyle(RoundedTextFieldStyle())
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                        }
                        
                        // Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            
                            SecureField("Enter your password", text: $password)
                                .textFieldStyle(RoundedTextFieldStyle())
                                .textContentType(.password)
                        }
                        
                        // Remember email toggle
                        Toggle(isOn: $rememberEmail) {
                            Text("Remember my email")
                                .foregroundColor(.white)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))
                        
                        // Login button
                        Button(action: login) {
                            Text("Log In")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.white)
                                .foregroundColor(circlesBlue)
                                .cornerRadius(25)
                        }
                        .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                        
                        // Forgot password link
                        Button("Forgot Password?") {
                            // TODO: Implement forgot password
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .font(.footnote)
                    }
                    .padding(.horizontal, 30)
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            if !savedEmail.isEmpty {
                email = savedEmail
            }
        }
        .alert("Login Error", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
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
    
    private func login() {
        Task {
            do {
                try await authManager.login(email: email, password: password)
                
                // Save email if remember is on
                if rememberEmail {
                    savedEmail = email
                } else {
                    savedEmail = ""
                }
                
                dismiss()
            } catch {
                if let authError = error as? AuthError {
                    alertMessage = authError.errorDescription ?? "Login failed"
                } else {
                    alertMessage = error.localizedDescription
                }
                showingAlert = true
            }
        }
    }
}

// Custom text field style
struct RoundedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.white.opacity(0.2))
            .cornerRadius(10)
            .foregroundColor(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
}

#Preview {
    EmailLoginView()
        .environmentObject(AuthManager.shared)
}