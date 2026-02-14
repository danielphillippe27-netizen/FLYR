import SwiftUI
import UIKit

/// Modal to connect Follow Up Boss: paste API key, validate locally, send to backend only.
/// Backend verifies with FUB and stores encrypted key; app never stores the key.
struct ConnectFUBView: View {
    @State private var apiKeyText = ""
    @State private var showApiKey = false
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @FocusState private var apiKeyFocused: Bool

    var onSuccess: () -> Void
    var onCancel: () -> Void

    private var trimmedKey: String {
        apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isKeyValid: Bool {
        trimmedKey.count >= 20
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Enter your Follow Up Boss API key")
                            .font(.flyrHeadline)
                            .foregroundColor(.text)

                        HStack(spacing: 12) {
                            if showApiKey {
                                TextField("API Key", text: $apiKeyText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .focused($apiKeyFocused)
                            } else {
                                SecureField("API Key", text: $apiKeyText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .focused($apiKeyFocused)
                            }
                            Button(showApiKey ? "Hide" : "Show") {
                                showApiKey.toggle()
                            }
                            .font(.flyrSubheadline)
                            .foregroundColor(.info)
                        }
                        .padding(12)
                        .background(Color.bgSecondary)
                        .cornerRadius(12)
                        .disabled(isConnecting)

                        Button("Paste") {
                            if let str = UIPasteboard.general.string {
                                apiKeyText = str.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .font(.flyrSubheadline)
                        .foregroundColor(.info)
                        .disabled(isConnecting)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("How to get your API key")
                                .font(.flyrSystem(size: 15, weight: .semibold))
                                .foregroundColor(.text)
                            Text("1) Open Follow Up Boss (desktop works best)")
                            Text("2) Go to Settings → Integrations / API")
                            Text("3) Generate API Key (or \"Create Key\")")
                            Text("4) Copy and paste it here")
                            Text("5) Tap Connect")
                                .padding(.bottom, 4)
                        }
                        .font(.flyrSubheadline)
                        .foregroundColor(.secondary)

                        if let err = errorMessage {
                            Text(err)
                                .font(.flyrSubheadline)
                                .foregroundColor(.error)
                        }

                        Spacer(minLength: 24)

                        Text("We encrypt your key and only use it to sync leads/notes you create in FLYR.")
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
                ToolbarItem(placement: .confirmationAction) {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Button("Connect") {
                            connect()
                        }
                        .disabled(!isKeyValid)
                    }
                }
            }
        }
        .onAppear {
            errorMessage = nil
        }
    }

    private func connect() {
        errorMessage = nil
        if !isKeyValid {
            errorMessage = "API key looks too short."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isConnecting = true
        Task {
            do {
                _ = try await FUBConnectAPI.shared.connect(apiKey: trimmedKey)
                await MainActor.run {
                    isConnecting = false
                    HapticManager.success()
                    if let userId = AuthManager.shared.user?.id {
                        Task { await CRMConnectionStore.shared.refresh(userId: userId) }
                    }
                    onSuccess()
                }
            } catch let e as FUBConnectError {
                await MainActor.run {
                    errorMessage = e.errorDescription ?? "Couldn't connect. Check your API key and try again."
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "No connection—try again."
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    isConnecting = false
                }
            }
        }
    }
}

#Preview {
    ConnectFUBView(onSuccess: {}, onCancel: {})
}
