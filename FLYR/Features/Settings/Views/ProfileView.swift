import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showImagePicker = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile Picture Section
                VStack(spacing: 16) {
                    ZStack {
                        if let image = viewModel.profileImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                )
                        } else {
                            // Use ProfileAvatarView as fallback
                            ProfileAvatarView(
                                avatarUrl: nil,
                                name: viewModel.profile?.displayName ?? viewModel.profile?.email ?? "User",
                                size: 120
                            )
                        }
                        
                        // Camera overlay button
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button {
                                    showImagePicker = true
                                } label: {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Color.accentDefault)
                                        .clipShape(Circle())
                                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                                }
                            }
                            .padding(.trailing, 4)
                            .padding(.bottom, 4)
                        }
                        .frame(width: 120, height: 120)
                    }
                    
                    Button {
                        showImagePicker = true
                    } label: {
                        Text("Change Photo")
                            .font(.callout)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.top, 20)
                
                // Sticky Card Form
                VStack(spacing: 20) {
                    // First Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("First Name")
                            .font(.flyrSubheadline)
                            .foregroundColor(.text)
                        TextField("First Name", text: $viewModel.firstName)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                    }
                    
                    // Last Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Name")
                            .font(.flyrSubheadline)
                            .foregroundColor(.text)
                        TextField("Last Name", text: $viewModel.lastName)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                    }
                    
                    // Nickname (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Nickname")
                                .font(.flyrSubheadline)
                                .foregroundColor(.text)
                            Text("(optional)")
                                .font(.flyrCaption)
                                .foregroundColor(.muted)
                        }
                        TextField("Nickname (overrides display name)", text: $viewModel.nickname)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                    }
                    
                    // Quote
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile Quote")
                            .font(.flyrSubheadline)
                            .foregroundColor(.text)
                        TextField("Your quote", text: $viewModel.quote, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .autocapitalization(.sentences)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.15), radius: 14, x: 0, y: 6)
                )
                .padding(.horizontal, 20)
                
                // Loading/Saving indicator
                if viewModel.isLoading || viewModel.isSaving {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(viewModel.isLoading ? "Loading..." : "Saving...")
                            .font(.flyrCaption)
                            .foregroundColor(.muted)
                    }
                    .padding(.top, 8)
                }
                
                // Error message
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.flyrCaption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                
                Spacer(minLength: 40)
            }
            .padding(.top, 20)
        }
        .background(Color.bg.ignoresSafeArea())
        .sheet(isPresented: $showImagePicker) {
            ImagePicker { image in
                viewModel.updateProfileImage(image)
            }
        }
        .onAppear {
            Task {
                await viewModel.loadProfile()
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}


