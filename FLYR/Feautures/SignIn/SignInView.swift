import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @StateObject private var auth = AuthManager.shared
    @State private var isSigningIn = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastType: ToastType = .success
    
    // Email/Password form state
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUpMode = false
    @State private var showPassword = false

    enum ToastType {
        case success, error
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: 60)
                        
                        // FLYR Branding
                        VStack(spacing: 8) {
                            Text("FLYR")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .padding(.top, 40)
                        
                        // Email/Password Form
                        VStack(spacing: 20) {
                            // Email Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                TextField("Enter your email", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .textFieldStyle(.plain)
                                    .padding(16)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            
                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    if showPassword {
                                        TextField("Enter your password", text: $password)
                                            .textContentType(isSignUpMode ? .newPassword : .password)
                                            .autocapitalization(.none)
                                    } else {
                                        SecureField("Enter your password", text: $password)
                                            .textContentType(isSignUpMode ? .newPassword : .password)
                                    }
                                    
                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .padding(16)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            
                            // Sign In/Up Button
                            Button {
                                Task { await handleEmailAuth() }
                            } label: {
                                HStack {
                                    if isSigningIn {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text(isSignUpMode ? "Sign Up" : "Sign In")
                                            .font(.system(size: 17, weight: .semibold))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(isFormValid ? Color.accentColor : Color.gray)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(isSigningIn || !isFormValid)
                            .scaleEffect(isSigningIn ? 0.98 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSigningIn)
                            
                            // Toggle Sign In/Sign Up
                            Button {
                                withAnimation {
                                    isSignUpMode.toggle()
                                    password = ""
                                }
                            } label: {
                                Text(isSignUpMode ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(height: 1)
                            
                            Text("OR")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                            
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 32)
                        
                        // Apple Sign-In Button
                        Button {
                            Task { await signInWithApple() }
                        } label: {
                            HStack {
                                if isSigningIn {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "applelogo")
                                        .font(.system(size: 18, weight: .medium))
                                }
                                
                                Text("Sign in with Apple")
                                    .font(.system(size: 17, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(isSigningIn)
                        .padding(.horizontal, 32)
                        
                        Spacer()
                            .frame(height: 40)
                    }
                }
                
                // Toast overlay
                if showToast {
                    VStack {
                        Spacer()
                        
                        HStack {
                            Image(systemName: toastType == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(toastType == .success ? .green : .red)
                            
                            Text(toastMessage)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 50)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showToast)
                }
            }
        }
    }
    
    // MARK: - Form Validation
    
    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@") && password.count >= 6
    }
    
    // MARK: - Email/Password Authentication
    
    private func handleEmailAuth() async {
        isSigningIn = true
        
        do {
            if isSignUpMode {
                try await auth.signUp(email: email, password: password)
                await MainActor.run {
                    displayToast(message: "Account created successfully 🎉", type: .success)
                }
            } else {
                try await auth.signIn(email: email, password: password)
                await MainActor.run {
                    displayToast(message: "Signed in successfully 🎉", type: .success)
                }
            }
        } catch {
            await MainActor.run {
                let errorMessage = error.localizedDescription
                displayToast(message: errorMessage.isEmpty ? "Authentication failed. Please try again." : errorMessage, type: .error)
            }
        }
        
        isSigningIn = false
    }
    
    // MARK: - Apple Sign-In
    
    private func signInWithApple() async {
        isSigningIn = true
        
        do {
            try await auth.signInWithApple()
            await MainActor.run {
                displayToast(message: "Signed in successfully 🎉", type: .success)
            }
        } catch {
            await MainActor.run {
                displayToast(message: "Sign-in failed. Try again.", type: .error)
            }
        }
        
        isSigningIn = false
    }
    
    private func displayToast(message: String, type: ToastType) {
        toastMessage = message
        toastType = type
        showToast = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showToast = false
            }
        }
    }
}
