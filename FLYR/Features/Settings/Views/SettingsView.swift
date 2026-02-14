import SwiftUI

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @StateObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var uiState: AppUIState
    
    @State private var followUpBossKey: String = ""
    @State private var excludeWeekends: Bool = false
    @State private var darkMode: Bool = true
    
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

                    // Apple Health
                    appleHealthSection
                    
                    // App Info
                    appInfoSection

                    #if DEBUG
                    debugSection
                    #endif
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
                    vm.refreshStepsIfEnabled()
                }
            }
            .onChange(of: vm.settings) { newSettings in
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

                        Text("FLYR™ Pro")
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
                HStack {
                    Image(systemName: "link.circle.fill")
                        .foregroundColor(.info)
                    Text("CRM Integrations")
                        .foregroundColor(.text)
                }
            }
        } header: {
            Text("Integrations")
        } footer: {
            Text("Connect your CRM to automatically sync leads from FLYR")
        }
    }
    
    // MARK: - Streak Settings Section
    
    private var streakSettingsSection: some View {
        Section {
            Toggle("Exclude Weekends from Streak", isOn: $excludeWeekends)
                .onChange(of: excludeWeekends) { newValue in
                    saveExcludeWeekends(newValue)
                }
        } header: {
            Text("Streak Settings")
        }
    }
    
    // MARK: - Appearance Section
    
    private var appearanceSection: some View {
        Section {
            Toggle("Dark Mode", isOn: $darkMode)
                .onChange(of: darkMode) { newValue in
                    saveDarkMode(newValue)
                }
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Apple Health Section

    private var appleHealthSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { vm.syncSteps },
                set: { newValue in
                    vm.syncSteps = newValue
                    vm.toggleHealthSync(newValue)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Steps")
                    Text("Show today's steps in the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.syncSteps {
                HStack {
                    Text("Today")
                    Spacer()
                    if vm.isLoadingSteps {
                        ProgressView()
                    } else if let steps = vm.todaySteps {
                        Text("\(steps)")
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Refresh Steps") {
                    vm.refreshStepsIfEnabled()
                }
            }

            if let err = vm.healthError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Apple Health")
        }
    }
    
    // MARK: - App Info Section
    
    private var appInfoSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.muted)
            }
            
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

    #if DEBUG
    private var debugSection: some View {
        Section {
            Button("Reset Onboarding") {
                LocalStorage.shared.hasCompletedOnboarding = false
                dismiss()
            }
        } header: {
            Text("Developer")
        }
    }
    #endif
    
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
}

