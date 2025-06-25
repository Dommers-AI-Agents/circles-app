import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingSuccessMessage = false
    
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
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Logo
                        VStack(spacing: 15) {
                            Image(systemName: "circle.grid.3x3.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white)
                            
                            Text("Create Account")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Join Circles to save and share your favorite places")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
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
                                
                                SecureField("Create a password", text: $password)
                                    .textFieldStyle(RoundedTextFieldStyle())
                                    .textContentType(.newPassword)
                                
                                Text("At least 6 characters")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            // Confirm password field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Confirm Password")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                SecureField("Confirm your password", text: $confirmPassword)
                                    .textFieldStyle(RoundedTextFieldStyle())
                                    .textContentType(.newPassword)
                            }
                            
                            // Create account button
                            Button(action: createAccount) {
                                Text("Create Account")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.white)
                                    .foregroundColor(circlesBlue)
                                    .cornerRadius(25)
                            }
                            .disabled(!isFormValid || authManager.isLoading)
                            
                            // Terms text
                            Text("By creating an account, you agree to our Terms of Service and Privacy Policy")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 30)
                        
                        Spacer(minLength: 50)
                    }
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
        .alert(alertTitle, isPresented: $showingAlert) {
            if showingSuccessMessage {
                Button("OK") {
                    dismiss()
                }
            } else {
                Button("OK", role: .cancel) { }
            }
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
    
    private var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        !confirmPassword.isEmpty &&
        password == confirmPassword &&
        password.count >= 6 &&
        email.contains("@") &&
        email.contains(".")
    }
    
    private func createAccount() {
        // Validate form
        guard isFormValid else {
            alertTitle = "Invalid Input"
            if password != confirmPassword {
                alertMessage = "Passwords don't match"
            } else if password.count < 6 {
                alertMessage = "Password must be at least 6 characters"
            } else if !email.contains("@") || !email.contains(".") {
                alertMessage = "Please enter a valid email address"
            }
            showingAlert = true
            return
        }
        
        Task {
            do {
                // Generate display name from email
                let displayName = email.components(separatedBy: "@").first ?? "User"
                
                try await authManager.register(
                    email: email,
                    password: password,
                    displayName: displayName
                )
                
                // Show success message
                alertTitle = "Verify Your Email"
                alertMessage = "A verification email has been sent to \(email). Please check your inbox and follow the link to verify your account before logging in."
                showingSuccessMessage = true
                showingAlert = true
            } catch {
                alertTitle = "Registration Error"
                if let authError = error as? AuthError {
                    alertMessage = authError.errorDescription ?? "Registration failed"
                } else {
                    alertMessage = error.localizedDescription
                }
                showingSuccessMessage = false
                showingAlert = true
            }
        }
    }
}

#Preview {
    RegistrationView()
        .environmentObject(AuthManager.shared)
}