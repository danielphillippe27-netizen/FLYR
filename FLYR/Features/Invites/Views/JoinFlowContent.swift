import SwiftUI

/// Content for join flow: validate, show workspace/email, then sign-in or accept button.
struct JoinFlowContent: View {
    let token: String
    @ObservedObject var viewModel: JoinFlowViewModel
    var onAcceptSuccess: () -> Void
    var onDismiss: () -> Void
    @EnvironmentObject var routeState: AppRouteState
    @StateObject private var auth = AuthManager.shared
    @State private var showSignIn = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.validated == nil {
                ProgressView("Checking invite…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = viewModel.errorMessage {
                joinErrorView(message: err)
            } else if let v = viewModel.validated {
                joinValidatedView(validation: v)
            } else {
                Button("Check invite") {
                    Task { await viewModel.validate(token: token) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel.validated == nil && viewModel.errorMessage == nil {
                await viewModel.validate(token: token)
            }
        }
    }

    private func joinErrorView(message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .multilineTextAlignment(.center)
                .padding()
            Button("Dismiss") { onDismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func joinValidatedView(validation: InviteValidateResponse) -> some View {
        VStack(spacing: 24) {
            Text("You're invited to join")
                .font(.headline)
            if let name = validation.workspaceName, !name.isEmpty {
                Text(name)
                    .font(.title2)
            }
            Text("Sign in with \(validation.email) to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if auth.user == nil {
                Button("Sign in") { showSignIn = true }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .buttonStyle(.borderedProminent)
                    .fullScreenCover(isPresented: $showSignIn) {
                        SignInView()
                            .onChange(of: auth.user?.id) { _, newId in
                                if newId != nil { showSignIn = false }
                            }
                    }
            } else {
                let userEmail = (auth.user?.email).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                let inviteEmail = validation.email.lowercased().trimmingCharacters(in: .whitespaces)
                let emailMatches = userEmail == inviteEmail
                if emailMatches {
                    Button("Accept invite") {
                        Task {
                            viewModel.isLoading = true
                            viewModel.errorMessage = nil
                            defer { viewModel.isLoading = false }
                            do {
                                try await viewModel.accept(token: token)
                                onAcceptSuccess()
                            } catch {
                                viewModel.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("This invite was sent to \(validation.email). Sign in with that email or sign out and use the correct account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Button("Cancel") { onDismiss() }
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
