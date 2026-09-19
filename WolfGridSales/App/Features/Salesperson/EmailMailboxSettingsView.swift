import SwiftUI

struct SalespersonEmailMailboxSettingsView: View {
    @ObservedObject var viewModel: SalespersonEmailMailboxViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var appSpecificPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Apple iCloud Mail", systemImage: "apple.logo")
                        .font(.headline)
                    Text("Connect the WolfGrid mailbox hosted by your Apple iCloud Custom Email Domain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Send and receive", value: WolfGridAppleMailbox.emailAddress)
                } header: {
                    Text("WolfGrid mailbox")
                } footer: {
                    Text("WolfGrid only imports mail addressed to this mailbox and always sends from this address.")
                }

                Section {
                    TextField("xxxx-xxxx-xxxx-xxxx", text: $appSpecificPassword)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Create an app-specific password", destination: URL(string: "https://account.apple.com/account/manage")!)
                } header: {
                    Text(viewModel.mailbox == nil ? "Apple app-specific password" : "New app-specific password (optional)")
                } footer: {
                    Text("Do not enter your normal Apple Account password. In Apple Account, open Sign-In and Security → App-Specific Passwords and create one for WolfGrid.")
                }

                if let mailbox = viewModel.mailbox {
                    Section("Status") {
                        LabeledContent("Mailbox", value: WolfGridAppleMailbox.emailAddress)
                        LabeledContent("Connection", value: mailbox.isActive ? "Connected" : "Disconnected")
                    }

                    Section {
                        Button("Disconnect iCloud Mail", role: .destructive) {
                            Task { await disconnect() }
                        }
                        .disabled(viewModel.isSaving)
                    } footer: {
                        Text("Existing WolfGrid email history remains available after disconnecting.")
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(viewModel.mailbox == nil ? "Connect Apple Email" : "Apple Email Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isSaving ? "Connecting…" : "Connect") {
                        Task { await save() }
                    }
                    .disabled(!canSave || viewModel.isSaving)
                }
            }
            .task {
                if viewModel.mailbox == nil { await viewModel.load() }
            }
        }
    }

    private var canSave: Bool {
        let passwordRequired = viewModel.mailbox == nil || viewModel.mailbox?.isActive == false
        return !passwordRequired || !appSpecificPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        let password = appSpecificPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        if await viewModel.save(
            appSpecificPassword: password.isEmpty ? nil : password,
            isActive: true
        ) { dismiss() }
    }

    private func disconnect() async {
        if await viewModel.save(appSpecificPassword: nil, isActive: false) {
            dismiss()
        }
    }
}

struct SalespersonEmailMailboxRow: View {
    let mailbox: SalespersonEmailMailbox?
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: mailbox?.isActive == true ? "checkmark.icloud.fill" : "icloud")
                    .font(.title3)
                    .foregroundStyle(mailbox?.isActive == true ? Color.green : Color.flyrPrimary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mailbox?.isActive == true ? "Apple email connected" : "Connect Apple email")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(mailbox?.emailAddress ?? WolfGridAppleMailbox.emailAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
