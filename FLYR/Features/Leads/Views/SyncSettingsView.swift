import SwiftUI
/// Sync settings sheet: connected CRM status, connect FUB/Zapier, export CSV, webhook.
struct SyncSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var auth = AuthManager.shared
    
    @State private var integrations: [UserIntegration] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAPIKeySheet = false
    @State private var showWebhookSheet = false
    @State private var apiKeyProvider: IntegrationProvider?
    @State private var webhookProvider: IntegrationProvider?
    @State private var apiKeyText = ""
    @State private var webhookURLText = ""
    @State private var isConnectingAPIKey = false
    @State private var isConnectingWebhook = false
    @State private var apiKeyError: String?
    @State private var webhookError: String?
    
    @State private var campaigns: [CampaignDBRow] = []
    @State private var showCampaignPicker = false
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportFileURL: URL?
    
    @State private var webhookURL: String = ""
    @State private var isTestingWebhook = false
    
    private var connectedProvider: IntegrationProvider? {
        integrations.first { $0.isConnected }?.provider
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        connectedSection
                        quickConnectSection
                        exportSection
                        webhookSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Sync Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadIntegrations() }
            .sheet(isPresented: $showAPIKeySheet) { apiKeySheet }
            .sheet(isPresented: $showWebhookSheet) { webhookSheet }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let e = errorMessage { Text(e) }
            }
        }
        .onAppear {
            webhookURL = UserDefaults.standard.string(forKey: "flyr_leads_webhook_url") ?? ""
        }
    }
    
    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connected")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            Text(connectedProvider?.displayName ?? "None")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.text)
        }
    }
    
    private var quickConnectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Connect")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            VStack(spacing: 12) {
                ForEach([IntegrationProvider.fub, .zapier], id: \.self) { provider in
                    let integration = integrations.first { $0.provider == provider }
                    HStack {
                        Image(systemName: provider.icon)
                            .font(.system(size: 20))
                            .foregroundColor(.accent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.text)
                            Text(provider.description)
                                .font(.system(size: 13))
                                .foregroundColor(.muted)
                        }
                        Spacer()
                        Button(integration?.isConnected == true ? "Connected" : (provider == .zapier ? "Setup →" : "Connect →")) {
                            handleConnect(provider: provider)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(integration?.isConnected == true ? .muted : .accent)
                        .disabled(integration?.isConnected == true)
                    }
                    .padding(16)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Export")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            Text("Export field leads as CSV for a campaign.")
                .font(.system(size: 13))
                .foregroundColor(.muted)
            Button(action: { Task { await loadCampaigns(); showCampaignPicker = true } }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export CSV for Campaign")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
            }
            .disabled(isExporting)
            .sheet(isPresented: $showCampaignPicker) {
                campaignPickerSheet
            }
        }
    }
    
    private var webhookSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Webhook (Advanced)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            TextField("POST URL", text: $webhookURL)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .keyboardType(.URL)
                .onChange(of: webhookURL) { _, v in
                    UserDefaults.standard.set(v, forKey: "flyr_leads_webhook_url")
                }
            Button("Test Webhook") {
                Task { await testWebhook() }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue)
            .cornerRadius(10)
            .disabled(webhookURL.isEmpty || isTestingWebhook)
        }
    }
    
    private var apiKeySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("API Key", text: $apiKeyText)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .disabled(isConnectingAPIKey)
                } header: {
                    Text("Enter your \(apiKeyProvider?.displayName ?? "CRM") API key")
                } footer: {
                    if let e = apiKeyError { Text(e).foregroundColor(.red) }
                }
            }
            .navigationTitle("Connect \(apiKeyProvider?.displayName ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showAPIKeySheet = false
                    }
                    .disabled(isConnectingAPIKey)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isConnectingAPIKey {
                        ProgressView()
                    } else {
                        Button("Connect") { connectWithAPIKey() }
                            .disabled(apiKeyText.isEmpty)
                    }
                }
            }
        }
    }
    
    private var webhookSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Webhook URL", text: $webhookURLText)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .disabled(isConnectingWebhook)
                } footer: {
                    if let e = webhookError { Text(e).foregroundColor(.red) }
                }
            }
            .navigationTitle("Connect Zapier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showWebhookSheet = false
                    }
                    .disabled(isConnectingWebhook)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isConnectingWebhook {
                        ProgressView()
                    } else {
                        Button("Connect") { connectWithWebhook() }
                            .disabled(webhookURLText.isEmpty)
                    }
                }
            }
        }
    }
    
    private func loadIntegrations() async {
        guard let userId = auth.user?.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            integrations = try await CRMIntegrationManager.shared.fetchIntegrations(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func handleConnect(provider: IntegrationProvider) {
        guard auth.user?.id != nil else { return }
        switch provider.connectionType {
        case .apiKey:
            apiKeyProvider = provider
            apiKeyText = ""
            apiKeyError = nil
            showAPIKeySheet = true
        case .webhook:
            webhookProvider = provider
            webhookURLText = ""
            webhookError = nil
            showWebhookSheet = true
        case .oauth:
            break
        }
    }
    
    private func connectWithAPIKey() {
        guard let provider = apiKeyProvider, let userId = auth.user?.id else { return }
        apiKeyError = nil
        isConnectingAPIKey = true
        Task {
            do {
                switch provider {
                case .fub:
                    try await CRMIntegrationManager.shared.connectFUB(userId: userId, apiKey: apiKeyText)
                case .kvcore:
                    try await CRMIntegrationManager.shared.connectKVCore(userId: userId, apiKey: apiKeyText)
                default:
                    break
                }
                await MainActor.run {
                    isConnectingAPIKey = false
                    showAPIKeySheet = false
                }
                await loadIntegrations()
            } catch {
                await MainActor.run {
                    isConnectingAPIKey = false
                    apiKeyError = error.localizedDescription
                }
            }
        }
    }
    
    private func connectWithWebhook() {
        guard let userId = auth.user?.id else { return }
        webhookError = nil
        isConnectingWebhook = true
        Task {
            do {
                try await CRMIntegrationManager.shared.connectZapier(userId: userId, webhookURL: webhookURLText)
                await MainActor.run {
                    isConnectingWebhook = false
                    showWebhookSheet = false
                }
                await loadIntegrations()
            } catch {
                await MainActor.run {
                    isConnectingWebhook = false
                    webhookError = error.localizedDescription
                }
            }
        }
    }
    
    private func loadCampaigns() async {
        do {
            campaigns = try await CampaignsAPI.shared.fetchCampaignsMetadata()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private var campaignPickerSheet: some View {
        NavigationStack {
            List(campaigns, id: \.id) { c in
                Button(c.title) {
                    showCampaignPicker = false
                    Task { await exportCampaignCSV(campaignId: c.id) }
                }
            }
            .navigationTitle("Select Campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { showCampaignPicker = false }
                }
            }
        }
    }
    
    private func exportCampaignCSV(campaignId: UUID) async {
        guard let userId = auth.user?.id else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let leads = try await FieldLeadsService.shared.fetchLeads(userId: userId, campaignId: campaignId)
            let url = try LeadsExportManager.exportToTempFile(
                leads: leads,
                filename: "field_leads_\(campaignId.uuidString.prefix(8)).csv"
            )
            await MainActor.run {
                exportFileURL = url
                showShareSheet = true
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func testWebhook() async {
        let urlString = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }
        isTestingWebhook = true
        defer { isTestingWebhook = false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let sample: [String: Any] = [
            "address": "123 Test St",
            "name": "Test Lead",
            "status": "interested",
            "source": "FLYR",
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: sample)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            await MainActor.run {
                errorMessage = code >= 200 && code < 300 ? nil : "Webhook returned \(code)"
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}

#Preview {
    SyncSettingsView()
}
