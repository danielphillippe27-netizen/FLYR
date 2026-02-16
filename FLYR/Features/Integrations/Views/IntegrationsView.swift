import SwiftUI
/// Main view for managing CRM integrations
struct IntegrationsView: View {
    @StateObject private var auth = AuthManager.shared
    @ObservedObject private var crmStore = CRMConnectionStore.shared
    @State private var integrations: [UserIntegration] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showOAuth = false
    @State private var oauthProvider: IntegrationProvider?
    @State private var showAPIKeySheet = false
    @State private var showWebhookSheet = false
    @State private var showConnectFUB = false
    @State private var apiKeyProvider: IntegrationProvider?
    @State private var webhookProvider: IntegrationProvider?
    @State private var apiKeyText = ""
    @State private var webhookURLText = ""
    @State private var showTestLeadAlert = false
    @State private var testLeadSent = false
    @State private var isConnectingAPIKey = false
    @State private var isConnectingWebhook = false
    @State private var apiKeyError: String?
    @State private var webhookError: String?
    @State private var fubActionMessage: String?
    @State private var fubActionSuccess: Bool = true
    @State private var isFUBActionInProgress = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // CRM Connections Section
                            Section {
                                VStack(spacing: 12) {
                                    ForEach(IntegrationProvider.allCases) { provider in
                                        let integration = integrations.first { $0.provider == provider }
                                        let crmConnection = provider == .fub ? crmStore.fubConnection : nil
                                        IntegrationCardView(
                                            provider: provider,
                                            integration: integration,
                                            crmConnection: crmConnection,
                                            onConnect: { handleConnect(provider: provider) },
                                            onDisconnect: { handleDisconnect(provider: provider) }
                                        )
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("CRM Connections")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                            }

                            // Follow Up Boss actions (when connected)
                            if crmStore.isFUBConnected {
                                Section {
                                    VStack(spacing: 12) {
                                        if let msg = fubActionMessage {
                                            Text(msg)
                                                .font(.system(size: 13))
                                                .foregroundColor(fubActionSuccess ? .success : .error)
                                                .multilineTextAlignment(.center)
                                        }
                                        HStack(spacing: 12) {
                                            Button(action: { runFUBTestConnection() }) {
                                                HStack(spacing: 6) {
                                                    if isFUBActionInProgress { ProgressView().scaleEffect(0.8).tint(.white) }
                                                    Text("Test connection")
                                                        .font(.system(size: 15, weight: .medium))
                                                }
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(Color.info)
                                                .cornerRadius(10)
                                            }
                                            .disabled(isFUBActionInProgress)
                                            Button(action: { runFUBTestPush() }) {
                                                Text("Send test lead")
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(.white)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 12)
                                                    .background(Color.info)
                                                    .cornerRadius(10)
                                            }
                                            .disabled(isFUBActionInProgress)
                                        }
                                        Button(action: { runFUBSyncCRM() }) {
                                            HStack(spacing: 6) {
                                                if isFUBActionInProgress { ProgressView().scaleEffect(0.8).tint(.white) }
                                                Text("Sync to CRM")
                                                    .font(.system(size: 15, weight: .medium))
                                            }
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.success)
                                            .cornerRadius(10)
                                        }
                                        .disabled(isFUBActionInProgress)
                                    }
                                    .padding(16)
                                    .background(Color.bgSecondary)
                                    .cornerRadius(20)
                                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                                } header: {
                                    HStack {
                                        Text("Follow Up Boss")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundColor(.text)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            
                            // Test Lead Section
                            Section {
                                VStack(spacing: 12) {
                                    Button(action: {
                                        sendTestLead()
                                    }) {
                                        HStack {
                                            Image(systemName: "paperplane.fill")
                                                .font(.system(size: 16))
                                            Text("Send Test Lead")
                                                .font(.system(size: 17, weight: .semibold))
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.info)
                                        .cornerRadius(12)
                                    }
                                    
                                    Text("Send a test lead to all connected CRMs to verify your integration")
                                        .font(.system(size: 13))
                                        .foregroundColor(.muted)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(16)
                                .background(Color.bgSecondary)
                                .cornerRadius(20)
                                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                            } header: {
                                HStack {
                                    Text("Automation")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle("Integrations")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadIntegrations()
                HapticManager.rigid()
            }
            .task {
                await loadIntegrations()
            }
            .sheet(isPresented: $showOAuth) {
                if let provider = oauthProvider, let userId = auth.user?.id {
                    OAuthView(
                        provider: provider,
                        userId: userId,
                        onComplete: { result in
                            showOAuth = false
                            Task {
                                await loadIntegrations()
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showAPIKeySheet) {
                apiKeyInputSheet
            }
            .sheet(isPresented: $showWebhookSheet) {
                webhookInputSheet
            }
            .sheet(isPresented: $showConnectFUB) {
                ConnectFUBView(
                    onSuccess: {
                        showConnectFUB = false
                        guard let userId = auth.user?.id else { return }
                        Task {
                            await CRMConnectionStore.shared.refresh(userId: userId)
                            await loadIntegrations()
                        }
                    },
                    onCancel: { showConnectFUB = false }
                )
            }
            .alert("Test Lead Sent", isPresented: $showTestLeadAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Lead sent to CRM")
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleConnect(provider: IntegrationProvider) {
        guard auth.user?.id != nil else { return }
        if provider == .fub {
            showConnectFUB = true
            return
        }
        switch provider.connectionType {
        case .oauth:
            oauthProvider = provider
            showOAuth = true
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
        }
    }
    
    private func handleDisconnect(provider: IntegrationProvider) {
        guard let userId = auth.user?.id else { return }
        if provider == .fub {
            Task {
                do {
                    try await FUBConnectAPI.shared.disconnect()
                    await CRMConnectionStore.shared.refresh(userId: userId)
                    await loadIntegrations()
                } catch {
                    errorMessage = "Failed to disconnect: \(error.localizedDescription)"
                }
            }
            return
        }
        Task {
            do {
                try await CRMIntegrationManager.shared.disconnect(userId: userId, provider: provider)
                await loadIntegrations()
            } catch {
                errorMessage = "Failed to disconnect: \(error.localizedDescription)"
            }
        }
    }
    
    private func loadIntegrations() async {
        guard let userId = auth.user?.id else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let integrationsTask = CRMIntegrationManager.shared.fetchIntegrations(userId: userId)
            async let crmTask = CRMConnectionStore.shared.refresh(userId: userId)
            integrations = try await integrationsTask
            await crmTask
        } catch {
            let msg = error.localizedDescription
            // Table missing (migration not applied): show as no integrations instead of blocking error
            if msg.contains("user_integrations") && (msg.contains("schema cache") || msg.contains("does not exist")) {
                integrations = []
                await CRMConnectionStore.shared.refresh(userId: userId)
                return
            }
            errorMessage = "Failed to load integrations: \(msg)"
            print("❌ Error loading integrations: \(error)")
        }
    }
    
    private func sendTestLead() {
        guard let userId = auth.user?.id else { return }
        
        let testLead = LeadModel(
            name: "Test Lead",
            phone: "555-555-5555",
            email: "test@flyr.app",
            address: "123 Test St",
            source: "FLYR Test",
            notes: "This is a test lead from FLYR"
        )
        
        Task {
            await LeadSyncManager.shared.syncLeadToCRM(lead: testLead, userId: userId)
            await MainActor.run {
                showTestLeadAlert = true
            }
        }
    }

    private func runFUBTestConnection() {
        fubActionMessage = nil
        isFUBActionInProgress = true
        Task {
            do {
                let res = try await FUBPushLeadAPI.shared.testConnection()
                await MainActor.run {
                    isFUBActionInProgress = false
                    fubActionSuccess = true
                    fubActionMessage = res.message ?? "Connection is working."
                }
            } catch {
                await MainActor.run {
                    isFUBActionInProgress = false
                    fubActionSuccess = false
                    fubActionMessage = error.localizedDescription
                }
            }
        }
    }

    private func runFUBTestPush() {
        fubActionMessage = nil
        isFUBActionInProgress = true
        Task {
            do {
                let res = try await FUBPushLeadAPI.shared.testPush()
                await MainActor.run {
                    isFUBActionInProgress = false
                    fubActionSuccess = true
                    fubActionMessage = res.message ?? "Test lead sent."
                }
            } catch {
                await MainActor.run {
                    isFUBActionInProgress = false
                    fubActionSuccess = false
                    fubActionMessage = error.localizedDescription
                }
            }
        }
    }

    private func runFUBSyncCRM() {
        fubActionMessage = nil
        isFUBActionInProgress = true
        Task {
            do {
                let res = try await FUBPushLeadAPI.shared.syncCRM()
                await MainActor.run {
                    isFUBActionInProgress = false
                    fubActionSuccess = true
                    fubActionMessage = res.message ?? "Synced \(res.synced ?? 0) contacts."
                }
            } catch {
                await MainActor.run {
                    isFUBActionInProgress = false
                    fubActionSuccess = false
                    fubActionMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Sheets
    
    private var apiKeyInputSheet: some View {
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
                    if let error = apiKeyError {
                        Text(error)
                            .foregroundColor(.red)
                    } else {
                        Text("Your API key is stored securely and only used to sync leads.")
                    }
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
                        Button("Connect") {
                            connectWithAPIKey()
                        }
                        .disabled(apiKeyText.isEmpty)
                    }
                }
            }
        }
    }
    
    private var webhookInputSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Webhook URL", text: $webhookURLText)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(isConnectingWebhook)
                } header: {
                    Text("Enter your Zapier webhook URL")
                } footer: {
                    if let error = webhookError {
                        Text(error)
                            .foregroundColor(.red)
                    } else {
                        Text("When a new lead is created, it will be sent to this webhook URL.")
                    }
                }
            }
            .navigationTitle("Connect \(webhookProvider?.displayName ?? "")")
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
                        Button("Connect") {
                            connectWithWebhook()
                        }
                        .disabled(webhookURLText.isEmpty)
                    }
                }
            }
        }
    }
    
    private func connectWithAPIKey() {
        guard let provider = apiKeyProvider,
              let userId = auth.user?.id else { return }
        
        // Reset error and start loading
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
                // Only close sheet on success
                await MainActor.run {
                    isConnectingAPIKey = false
                    showAPIKeySheet = false
                }
                await loadIntegrations()
            } catch {
                // Keep sheet open and show error
                await MainActor.run {
                    isConnectingAPIKey = false
                    apiKeyError = "Failed to connect: \(error.localizedDescription)"
                    print("❌ Error connecting integration: \(error)")
                }
            }
        }
    }
    
    private func connectWithWebhook() {
        guard let provider = webhookProvider,
              let userId = auth.user?.id else { return }
        
        // Reset error and start loading
        webhookError = nil
        isConnectingWebhook = true
        
        Task {
            do {
                try await CRMIntegrationManager.shared.connectZapier(userId: userId, webhookURL: webhookURLText)
                // Only close sheet on success
                await MainActor.run {
                    isConnectingWebhook = false
                    showWebhookSheet = false
                }
                await loadIntegrations()
            } catch {
                // Keep sheet open and show error
                await MainActor.run {
                    isConnectingWebhook = false
                    webhookError = "Failed to connect: \(error.localizedDescription)"
                    print("❌ Error connecting webhook: \(error)")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    IntegrationsView()
}

