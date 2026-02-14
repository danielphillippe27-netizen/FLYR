import SwiftUI

struct ProfileSetupScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showingImagePicker = false

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Text("Profile setup")
                    .font(.system(size: 28, weight: .bold))
                Text("We'll use this to personalize your experience.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Full name (required)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        TextField("First name", text: $viewModel.response.firstName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.givenName)
                            .autocapitalization(.words)
                        TextField("Last name", text: $viewModel.response.lastName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.familyName)
                            .autocapitalization(.words)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile photo (optional)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Button {
                        showingImagePicker = true
                    } label: {
                        if let image = viewModel.profileImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 100, height: 100)
                                VStack(spacing: 4) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 28))
                                    Text("Add photo")
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 16) {
                Button(action: { viewModel.next() }) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(viewModel.canProceed ? Color.flyrPrimary : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!viewModel.canProceed)
                Button(action: { viewModel.back() }) {
                    Text("Back")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker { image in
                viewModel.profileImage = image
            }
        }
    }
}
