import SwiftUI
import UIKit

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @StateObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var uiState: AppUIState
    @State private var followUpBossKey: String = ""
    @State private var excludeWeekends: Bool = false
    @State private var darkMode: Bool = true
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if let user = auth.user {
                    // Profile Section
                    profileSection(user: user)
                    
                    // Integrations Section
                    integrationsSection

                    // Streak Settings
                    streakSettingsSection
                    
                    // Appearance
                    appearanceSection

                    // App Info
                    appInfoSection
                } else {
                    Section {
                        Text("Please sign in to view settings")
                            .foregroundColor(.muted)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if let userID = auth.user?.id {
                    await vm.loadSettings(for: userID)
                    // Initialize local state from loaded settings
                    if let settings = vm.settings {
                        followUpBossKey = settings.follow_up_boss_key ?? ""
                        excludeWeekends = settings.exclude_weekends
                        darkMode = settings.dark_mode
                    }
                }
            }
            .onChange(of: vm.settings) { _, newSettings in
                if let settings = newSettings {
                    followUpBossKey = settings.follow_up_boss_key ?? ""
                    excludeWeekends = settings.exclude_weekends
                    darkMode = settings.dark_mode
                }
            }
            .onAppear {
                if let userID = auth.user?.id {
                    Task { await vm.loadProfile(userID: userID) }
                }
            }
            .confirmationDialog(
                "Delete Account?",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes your WolfGrid account from Supabase and cannot be undone.")
            }
            .alert(
                "Delete Account Failed",
                isPresented: Binding(
                    get: { deleteAccountError != nil },
                    set: { if !$0 { deleteAccountError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAccountError ?? "")
            }
        }
    }
    
    // MARK: - Profile Section

    private func profileSection(user: AppUser) -> some View {
        Section {
            NavigationLink(destination: ProfileView()) {
                HStack(spacing: 16) {
                    Group {
                        if let photoURL = user.photoURL {
                            AsyncImage(url: photoURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure, .empty:
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.muted)
                                @unknown default:
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.muted)
                                }
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.bgSecondary)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.muted)
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.profile?.displayName ?? user.displayName ?? user.email)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.text)

                        Text("WolfGrid Sales")
                            .font(.system(size: 13))
                            .foregroundColor(.info)

                        if let settings = vm.settings,
                           let memberSince = settings.formattedMemberSince {
                            Text("Member for \(memberSince)")
                                .font(.system(size: 12))
                                .foregroundColor(.muted)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 8)
            }
        } header: {
            Text("Profile")
        }
    }
    
    // MARK: - Integrations Section
    
    private var integrationsSection: some View {
        Section {
            NavigationLink(destination: IntegrationsView()) {
                integrationsRowContent
            }
        } header: {
            Text("Integrations")
        } footer: {
            Text("Connect your CRM to automatically sync leads from WolfGrid")
        }
    }

    private var integrationsRowContent: some View {
        HStack {
            Image(systemName: "link.circle.fill")
                .foregroundColor(.info)
            Text("CRM Integrations")
        }
    }

    // MARK: - Streak Settings Section
    
    private var streakSettingsSection: some View {
        Section {
            Toggle("Exclude Weekends from Streak", isOn: $excludeWeekends)
                .onChange(of: excludeWeekends) { _, newValue in
                    saveExcludeWeekends(newValue)
                }
        } header: {
            Text("Streak Settings")
        }
    }
    
    // MARK: - Appearance Section
    
    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $darkMode) {
                Label("Light", systemImage: "sun.max.fill")
                    .tag(false)
                Label("Dark", systemImage: "moon.fill")
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: darkMode) { _, newValue in
                saveDarkMode(newValue)
            }
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - App Info Section
    
    private var appInfoSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersionText)
                    .foregroundColor(.muted)
            }

            Button("Terms of Use (EULA)") {
                openExternalURL("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
            }

            Button("Privacy Policy") {
                openExternalURL("https://sales.wolfgrid.app/privacy")
            }

            Button(role: .destructive) {
                showDeleteAccountConfirm = true
            } label: {
                if isDeletingAccount {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Deleting Account...")
                    }
                } else {
                    Text("Delete Account")
                }
            }
            .disabled(isDeletingAccount)
            
            Button(role: .destructive) {
                Task {
                    await auth.signOut()
                    dismiss()
                }
            } label: {
                Text("Log Out")
            }
        } header: {
            Text("App Info")
        }
    }
    
    // MARK: - Save Methods
    
    private func saveFollowUpBossKey() {
        guard let userID = auth.user?.id else { return }
        Task {
            await vm.updateSetting(userID: userID, key: "follow_up_boss_key", value: followUpBossKey.isEmpty ? NSNull() : followUpBossKey)
        }
    }
    
    private func saveExcludeWeekends(_ value: Bool) {
        guard let userID = auth.user?.id else { return }
        Task {
            await vm.updateSetting(userID: userID, key: "exclude_weekends", value: value)
        }
    }
    
    private func saveDarkMode(_ value: Bool) {
        guard let userID = auth.user?.id else { return }
        Task {
            // Update the app's appearance immediately
            await uiState.updateAppearancePreference(userID: userID, isDarkMode: value)
            // Also save via view model (for consistency)
            await vm.updateSetting(userID: userID, key: "dark_mode", value: value)
        }
    }

    private func openExternalURL(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        Task {
            await UIApplication.shared.open(url)
        }
    }

    @MainActor
    private func deleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        deleteAccountError = nil
        defer { isDeletingAccount = false }

        do {
            try await AccessAPI.shared.deleteCurrentAccount()
            await auth.signOut()
            dismiss()
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }
}
