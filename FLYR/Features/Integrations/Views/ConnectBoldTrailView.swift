import SwiftUI
import UIKit

struct ConnectBoldTrailView: View {
    @Environment(\.dismiss) private var dismiss

    let existingConnection: CRMConnection?
    var onSuccess: () -> Void
    var onCancel: () -> Void
    var onDisconnect: (() -> Void)?

    @State private var apiToken = ""
    @State private var showToken = false
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var testMessage: String?
    @State private var lastTestedToken: String?
    @State private var lastTestSucceeded = false

    private var trimmedToken: String {
        apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasStoredToken: Bool {
        existingConnection?.isConnected == true
    }

    private var canSave: Bool {
        !trimmedToken.isEmpty && lastTestSucceeded && lastTestedToken == trimmedToken
    }

    private var tokenHint: String? {
        existingConnection?.metadata?.tokenHint
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Connect BoldTrail / kvCORE")
                            .font(.flyrHeadline)
                            .foregroundColor(.text)

                        Text("Generate your API token in BoldTrail / kvCORE and paste it here.")
                            .font(.flyrSubheadline)
                            .foregroundColor(.secondary)

                        if let tokenHint {
                            Label("Saved token: \(tokenHint)", systemImage: "lock.fill")
                                .font(.flyrSubheadline)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Group {
                                    if showToken {
                                        TextField("API token", text: $apiToken)
                                    } else {
                                        SecureField("API token", text: $apiToken)
                                    }
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                                Button(showToken ? "Hide" : "Show") {
                                    showToken.toggle()
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.accent)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.bgSecondary)
                            .cornerRadius(12)

                            Button("Paste from Clipboard") {
                                if let pasted = UIPasteboard.general.string {
                                    apiToken = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.accent)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("What this MVP syncs")
                                .font(.flyrSystem(size: 15, weight: .semibold))
                                .foregroundColor(.text)
                            Text("Contacts and leads created in FLYR")
                            Text("One-way sync from FLYR to BoldTrail / kvCORE")
                            Text("Future notes, follow-ups, and appointments can plug into the same provider flow")
                        }
                        .font(.flyrSubheadline)
                        .foregroundColor(.secondary)

                        if let testMessage {
                            Text(testMessage)
                                .font(.flyrSubheadline)
                                .foregroundColor(lastTestSucceeded ? .success : .error)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.flyrSubheadline)
                                .foregroundColor(.error)
                        }

                        VStack(spacing: 12) {
                            Button {
                                testConnection()
                            } label: {
                                HStack {
                                    if isTesting {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(isTesting ? "Testing..." : testButtonTitle)
                                        .font(.flyrSystem(size: 16, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundColor(.white)
                                .background(Color.info)
                                .cornerRadius(12)
                            }
                            .disabled(isTesting || isSaving || (!hasStoredToken && trimmedToken.isEmpty))

                            Button {
                                saveToken()
                            } label: {
                                HStack {
                                    if isSaving {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(isSaving ? "Saving..." : saveButtonTitle)
                                        .font(.flyrSystem(size: 16, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundColor(.white)
                                .background(canSave ? Color.accent : Color.gray)
                                .cornerRadius(12)
                            }
                            .disabled(!canSave || isTesting || isSaving)
                        }

                        if let onDisconnect {
                            Button(role: .destructive) {
                                onDisconnect()
                                dismiss()
                            } label: {
                                Text("Disconnect BoldTrail")
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("BoldTrail / kvCORE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isTesting || isSaving)
                }
            }
        }
    }

    private var testButtonTitle: String {
        trimmedToken.isEmpty ? "Test Saved Token" : "Test Connection"
    }

    private var saveButtonTitle: String {
        "Save Token"
    }

    private func testConnection() {
        let tokenToTest = trimmedToken.isEmpty ? nil : trimmedToken
        errorMessage = nil
        testMessage = nil
        isTesting = true

        Task {
            do {
                let response = try await BoldTrailConnectAPI.shared.testConnection(apiToken: tokenToTest)
                await MainActor.run {
                    isTesting = false
                    lastTestSucceeded = true
                    lastTestedToken = tokenToTest ?? trimmedToken
                    testMessage = response.message ?? "Connection successful"
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    lastTestSucceeded = false
                    lastTestedToken = tokenToTest ?? trimmedToken
                    testMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveToken() {
        guard !trimmedToken.isEmpty else { return }
        errorMessage = nil
        isSaving = true

        Task {
            do {
                _ = try await BoldTrailConnectAPI.shared.connect(apiToken: trimmedToken)
                await MainActor.run {
                    isSaving = false
                    onSuccess()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    ConnectBoldTrailView(existingConnection: nil, onSuccess: {}, onCancel: {}, onDisconnect: nil)
}
