import SwiftUI

/// Modal to connect Follow Up Boss with OAuth.
/// The backend handles OAuth exchange and token storage; app never stores FUB credentials.
struct ConnectFUBView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    let existingConnection: CRMConnection?
    @State private var isConnecting = false
    @State private var isTestingConnection = false
    @State private var isSendingTestLead = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var onSuccess: () -> Void
    var onCancel: () -> Void
    var onDisconnect: (() -> Void)?

    private var isConnected: Bool {
        existingConnection?.isConnected == true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(isConnected ? "Manage Follow Up Boss" : "Connect Follow Up Boss")
                            .font(.flyrHeadline)
                            .foregroundColor(.text)

                        Text(
                            isConnected
                            ? "Your Follow Up Boss connection is active. You can verify it, send a test lead, or disconnect below."
                            : "Sign in to Follow Up Boss and approve access. FLYR will securely store OAuth tokens on the backend."
                        )
                            .font(.flyrSubheadline)
                            .foregroundColor(.secondary)

                        if isConnected {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Available actions")
                                    .font(.flyrSystem(size: 15, weight: .semibold))
                                    .foregroundColor(.text)
                                Text("1) Test the stored Follow Up Boss connection")
                                Text("2) Send a provider-specific test lead")
                                Text("3) Disconnect any time")
                            }
                            .font(.flyrSubheadline)
                            .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("What happens next")
                                    .font(.flyrSystem(size: 15, weight: .semibold))
                                    .foregroundColor(.text)
                                Text("1) Tap Continue")
                                Text("2) Sign in to Follow Up Boss")
                                Text("3) Approve access")
                                Text("4) Return to FLYR automatically")
                            }
                            .font(.flyrSubheadline)
                            .foregroundColor(.secondary)
                        }

                        if let successMessage {
                            Text(successMessage)
                                .font(.flyrSubheadline)
                                .foregroundColor(.success)
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(.flyrSubheadline)
                                .foregroundColor(.error)
                        }

                        Spacer(minLength: 24)

                        if isConnected {
                            VStack(spacing: 12) {
                                Button {
                                    testConnection()
                                } label: {
                                    HStack {
                                        if isTestingConnection {
                                            ProgressView().tint(.white)
                                        }
                                        Text(isTestingConnection ? "Testing…" : "Test Connection")
                                            .font(.flyrSystem(size: 16, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundColor(.white)
                                    .background(Color.info)
                                    .cornerRadius(12)
                                }
                                .disabled(isTestingConnection || isSendingTestLead)

                                Button {
                                    sendTestLead()
                                } label: {
                                    HStack {
                                        if isSendingTestLead {
                                            ProgressView().tint(.white)
                                        }
                                        Text(isSendingTestLead ? "Sending…" : "Send Test Lead")
                                            .font(.flyrSystem(size: 16, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundColor(.white)
                                    .background(Color.accent)
                                    .cornerRadius(12)
                                }
                                .disabled(isTestingConnection || isSendingTestLead)

                                if let onDisconnect {
                                    Button(role: .destructive) {
                                        onDisconnect()
                                        dismiss()
                                    } label: {
                                        Text("Disconnect Follow Up Boss")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        } else {
                            Button {
                                beginOAuth()
                            } label: {
                                HStack {
                                    if isConnecting {
                                        ProgressView().tint(.white)
                                    }
                                    Text(isConnecting ? "Opening…" : "Continue to Follow Up Boss")
                                        .font(.flyrSystem(size: 16, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundColor(.white)
                                .background(Color.accent)
                                .cornerRadius(12)
                            }
                            .disabled(isConnecting)
                        }

                        Text("You can disconnect anytime from Integrations.")
                            .font(.flyrCaption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Connect Follow Up Boss")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isConnecting)
                }
            }
        }
    }

    private func testConnection() {
        successMessage = nil
        errorMessage = nil
        isTestingConnection = true

        Task {
            do {
                let response = try await FUBPushLeadAPI.shared.testConnection()
                await MainActor.run {
                    isTestingConnection = false
                    successMessage = response.message ?? "Follow Up Boss connection is working."
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func sendTestLead() {
        successMessage = nil
        errorMessage = nil
        isSendingTestLead = true

        Task {
            do {
                let response = try await FUBPushLeadAPI.shared.testPush()
                await MainActor.run {
                    isSendingTestLead = false
                    successMessage = response.message ?? "Test lead sent to Follow Up Boss."
                }
            } catch {
                await MainActor.run {
                    isSendingTestLead = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func beginOAuth() {
        successMessage = nil
        errorMessage = nil
        isConnecting = true
        Task {
            do {
                let authorizeURL = try await FUBOAuthAPI.shared.fetchAuthorizeURL(platform: "ios")
                await MainActor.run {
                    isConnecting = false
                    #if DEBUG
                    print("🚀 [FUB OAuth] Opening authorize URL: \(authorizeURL.absoluteString)")
                    #endif
                    openURL(authorizeURL)
                    onCancel()
                }
            } catch {
                await MainActor.run {
                    #if DEBUG
                    print("❌ [FUB OAuth] Failed to begin OAuth: \(error.localizedDescription)")
                    #endif
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }
}

#Preview {
    ConnectFUBView(existingConnection: nil, onSuccess: {}, onCancel: {}, onDisconnect: nil)
}
