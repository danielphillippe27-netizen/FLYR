import SwiftUI
/// Sync settings sheet: connected CRM status, connect FUB/Zapier, export CSV, webhook.
struct SyncSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var auth = AuthManager.shared
    @ObservedObject private var crmStore = CRMConnectionStore.shared
    
    @State private var integrations: [UserIntegration] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAPIKeySheet = false
    @State private var showWebhookSheet = false
    @State private var showConnectFUB = false
    @State private var showConnectBoldTrail = false
    @State private var showOAuth = false
    @State private var showRequestCRMFeedback = false
    @State private var apiKeyProvider: IntegrationProvider?
    @State private var webhookProvider: IntegrationProvider?
    @State private var oauthProvider: IntegrationProvider?
    @State private var apiKeyText = ""
    @State private var webhookURLText = ""
    @State private var isConnectingAPIKey = false
    @State private var isConnectingWebhook = false
    @State private var isDisconnecting = false
    @State private var apiKeyError: String?
    @State private var webhookError: String?
    @State private var providerPendingDisconnect: IntegrationProvider?
    
    @State private var campaigns: [CampaignDBRow] = []
    @State private var showCampaignPicker = false
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportFileURL: URL?
    
    @State private var webhookURL: String = ""
    @State private var isTestingWebhook = false
    @State private var testingProvider: IntegrationProvider?
    @State private var successMessage: String?
    @State private var showMondayBoardSheet = false
    @State private var mondayBoards: [MondayBoardSummary] = []
    @State private var isLoadingMondayBoards = false
    @State private var isSavingMondayBoard = false
    @State private var mondayBoardsError: String?

    private var fubIntegration: UserIntegration? {
        integrations.first { $0.provider == .fub }
    }

    private var mondayIntegration: UserIntegration? {
        integrations.first { $0.provider == .monday }
    }

    private var isFUBConnected: Bool {
        crmStore.isFUBConnected || (fubIntegration?.isConnected == true)
    }

    private var isBoldTrailConnected: Bool {
        crmStore.boldtrailConnection?.isConnected == true
    }
    
    private var connectedProvider: IntegrationProvider? {
        if isFUBConnected { return .fub }
        if isBoldTrailConnected { return .boldtrail }
        return integrations.first { $0.isConnected }?.provider
    }

    private var connectedProviders: [IntegrationProvider] {
        var providers: [IntegrationProvider] = []
        if isFUBConnected {
            providers.append(.fub)
        }
        if isBoldTrailConnected {
            providers.append(.boldtrail)
        }
        for integration in integrations where integration.isConnected {
            if !providers.contains(integration.provider) {
                providers.append(integration.provider)
            }
        }
        return providers
    }

    private var testableProviders: [IntegrationProvider] {
        [.fub, .boldtrail, .hubspot, .monday].filter { connectedProviders.contains($0) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        connectedSection
                        quickConnectSection
                        requestCRMSection
                        testSection
                        exportSection
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
            .sheet(isPresented: $showOAuth) {
                if let provider = oauthProvider, let userId = auth.user?.id {
                    OAuthView(
                        provider: provider,
                        userId: userId,
                        onComplete: { result in
                            showOAuth = false
                            let oauthSucceeded: Bool
                            if case .failure(let error) = result {
                                oauthSucceeded = false
                                errorMessage = error.localizedDescription
                            } else {
                                oauthSucceeded = true
                            }
                            Task {
                                await loadIntegrations()
                                if oauthSucceeded && provider == .monday {
                                    await MainActor.run {
                                        presentMondayBoardPicker()
                                    }
                                }
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showConnectFUB) {
                ConnectFUBView(
                    existingConnection: crmStore.fubConnection,
                    onSuccess: {
                        showConnectFUB = false
                        guard let userId = auth.user?.id else { return }
                        Task {
                            await CRMConnectionStore.shared.refresh(userId: userId)
                            await loadIntegrations()
                        }
                    },
                    onCancel: { showConnectFUB = false },
                    onDisconnect: isFUBConnected ? {
                        disconnect(provider: .fub)
                    } : nil
                )
            }
            .sheet(isPresented: $showConnectBoldTrail) {
                ConnectBoldTrailView(
                    existingConnection: crmStore.boldtrailConnection,
                    onSuccess: {
                        showConnectBoldTrail = false
                        guard let userId = auth.user?.id else { return }
                        Task {
                            await CRMConnectionStore.shared.refresh(userId: userId)
                            await loadIntegrations()
                            await MainActor.run {
                                successMessage = "BoldTrail token saved."
                            }
                        }
                    },
                    onCancel: { showConnectBoldTrail = false },
                    onDisconnect: isBoldTrailConnected ? {
                        disconnect(provider: .boldtrail)
                    } : nil
                )
            }
            .sheet(isPresented: $showMondayBoardSheet) {
                mondayBoardPickerSheet
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .navigationDestination(isPresented: $showRequestCRMFeedback) {
                SupportChatView(
                    initialDraftMessage: """
                    Request New CRM Integration

                    CRM Name:
                    Why I need it:
                    """,
                    quickSuggestions: [
                        "Please add this CRM",
                        "I can help test this integration"
                    ]
                )
            }
            .alert("Disconnect \(providerPendingDisconnect?.displayName ?? "")?", isPresented: Binding(
                get: { providerPendingDisconnect != nil },
                set: { if !$0 { providerPendingDisconnect = nil } }
            )) {
                Button("Cancel", role: .cancel) {
                    providerPendingDisconnect = nil
                }
                Button("Disconnect", role: .destructive) {
                    guard let provider = providerPendingDisconnect else { return }
                    providerPendingDisconnect = nil
                    disconnect(provider: provider)
                }
            } message: {
                Text("This will remove the integration and stop future lead syncs.")
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let e = errorMessage { Text(e) }
            }
            .alert("Success", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
                Button("OK") { successMessage = nil }
            } message: {
                if let m = successMessage { Text(m) }
            }
        }
    }
    
    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connected")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            if connectedProviders.isEmpty {
                Text("None")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.text)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(connectedProviders, id: \.self) { provider in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.displayName)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.text)
                                if provider == .monday, let mondayIntegration {
                                    Text(mondayIntegration.selectedBoardName ?? "Board not selected")
                                        .font(.system(size: 13))
                                        .foregroundColor(mondayIntegration.mondayNeedsBoardSelection ? .orange : .muted)
                                }
                            }
                            Spacer()
                            Button("Disconnect") {
                                providerPendingDisconnect = provider
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .disabled(isDisconnecting)
                        }
                    }
                }
            }
        }
    }
    
    private var quickConnectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Connect")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            VStack(spacing: 12) {
                ForEach([IntegrationProvider.fub, .boldtrail, .hubspot, .monday], id: \.self) { provider in
                    let integration = integrations.first { $0.provider == provider }
                    let isConnected: Bool = {
                        switch provider {
                        case .fub:
                            return isFUBConnected
                        case .boldtrail:
                            return isBoldTrailConnected
                        default:
                            return integration?.isConnected == true
                        }
                    }()
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
                        let actionTitle = isConnected
                            ? "Manage →"
                            : (provider == .zapier ? "Setup →" : "Connect →")
                        Button(actionTitle) {
                            if isConnected {
                                if provider == .fub {
                                    showConnectFUB = true
                                } else if provider == .monday {
                                    presentMondayBoardPicker()
                                } else if provider == .boldtrail {
                                    showConnectBoldTrail = true
                                } else {
                                    providerPendingDisconnect = provider
                                }
                            } else {
                                handleConnect(provider: provider)
                            }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accent)
                        .disabled(isDisconnecting || isConnectingAPIKey || isConnectingWebhook)
                    }
                    .padding(16)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(12)
                }
            }

            if let mondayIntegration, mondayIntegration.isConnected {
                VStack(alignment: .leading, spacing: 8) {
                    Text(mondayIntegration.mondayNeedsBoardSelection
                         ? "Monday.com is connected but still needs a board before sync will run."
                         : "Sync target: \(mondayIntegration.selectedBoardName ?? "Monday board")")
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                    if let mondayBoardsError {
                        Text(mondayBoardsError)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }

    private var requestCRMSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Need Another CRM?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            Text("Send us your CRM request and we will prioritize new integrations.")
                .font(.system(size: 13))
                .foregroundColor(.muted)
            Button("Request New CRM") {
                showRequestCRMFeedback = true
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
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

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Testing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            Text("Send a provider-specific test lead to each connected CRM.")
                .font(.system(size: 13))
                .foregroundColor(.muted)
            if testableProviders.isEmpty {
                Text("Connect Follow Up Boss, BoldTrail / kvCORE, HubSpot, or Monday.com to enable test leads.")
                    .font(.system(size: 13))
                    .foregroundColor(.muted)
            } else {
                ForEach(testableProviders, id: \.self) { provider in
                    Button(action: { Task { await sendTestLead(to: provider) } }) {
                        HStack {
                            if testingProvider == provider {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(testingProvider == provider ? "Sending..." : "Send Test Lead to \(provider.displayName)")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(testButtonColor(for: provider))
                        .cornerRadius(12)
                    }
                    .disabled(testingProvider != nil || isDisconnecting || isLoading)
                }
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
    
    @MainActor
    private func loadIntegrations() async {
        guard let userId = auth.user?.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let integrationsTask = CRMIntegrationManager.shared.fetchIntegrations(userId: userId)
            async let crmTask: Void = CRMConnectionStore.shared.refresh(userId: userId)
            integrations = try await integrationsTask
            await crmTask
            await refreshMondayStatusIfNeeded()
        } catch {
            let message = error.localizedDescription
            if message.contains("user_integrations") &&
                (message.contains("schema cache") || message.contains("does not exist")) {
                integrations = []
                await CRMConnectionStore.shared.refresh(userId: userId)
                return
            }
            errorMessage = message
        }
    }
    
    private func handleConnect(provider: IntegrationProvider) {
        guard auth.user?.id != nil else { return }
        if provider == .fub {
            showConnectFUB = true
            return
        }
        if provider == .boldtrail {
            showConnectBoldTrail = true
            return
        }
        switch provider.connectionType {
        case .apiKey:
            apiKeyProvider = provider
            apiKeyText = ""
            apiKeyError = nil
            showAPIKeySheet = true
        case .token:
            showConnectBoldTrail = true
        case .webhook:
            webhookProvider = provider
            webhookURLText = ""
            webhookError = nil
            showWebhookSheet = true
        case .oauth:
            oauthProvider = provider
            showOAuth = true
        }
    }

    @MainActor
    private func presentMondayBoardPicker() {
        mondayBoardsError = nil
        isLoadingMondayBoards = true
        Task {
            do {
                let response = try await CRMIntegrationManager.shared.fetchMondayBoards()
                await MainActor.run {
                    mondayBoards = response.validBoards
                    applyMondayBoardsResponse(response)
                    isLoadingMondayBoards = false
                    showMondayBoardSheet = true
                    if response.validBoards.isEmpty {
                        mondayBoardsError = "No Monday boards were found for this account."
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingMondayBoards = false
                    mondayBoardsError = error.localizedDescription
                    errorMessage = mondayBoardsError
                }
            }
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
                    throw NSError(
                        domain: "SyncSettingsView",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Use the Follow Up Boss Connect flow."]
                    )
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

    private func disconnect(provider: IntegrationProvider) {
        guard let userId = auth.user?.id else { return }
        isDisconnecting = true
        Task {
            do {
                if provider == .fub {
                    try await FUBConnectAPI.shared.disconnect()
                    await CRMConnectionStore.shared.refresh(userId: userId)
                } else if provider == .boldtrail {
                    try await BoldTrailConnectAPI.shared.disconnect()
                    await CRMConnectionStore.shared.refresh(userId: userId)
                } else {
                    try await CRMIntegrationManager.shared.disconnect(userId: userId, provider: provider)
                }
                await loadIntegrations()
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to disconnect \(provider.displayName): \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                isDisconnecting = false
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

    private var mondayBoardPickerSheet: some View {
        NavigationStack {
            List {
                if let mondayBoardsError {
                    Section {
                        Text(mondayBoardsError)
                            .foregroundColor(.red)
                    }
                }

                if mondayBoards.isEmpty, !isLoadingMondayBoards {
                    Section {
                        Text("No Monday boards are available for this account yet.")
                            .foregroundColor(.muted)
                    }
                }

                ForEach(mondayBoards) { board in
                    Button(action: { selectMondayBoard(board) }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(board.name)
                                .foregroundColor(.text)
                            if let workspaceName = board.workspaceName, !workspaceName.isEmpty {
                                Text(workspaceName)
                                    .font(.system(size: 12))
                                    .foregroundColor(.muted)
                            }
                        }
                    }
                    .disabled(isSavingMondayBoard)
                }
            }
            .overlay {
                if isLoadingMondayBoards || isSavingMondayBoard {
                    ProgressView()
                }
            }
            .navigationTitle("Select Monday Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        showMondayBoardSheet = false
                    }
                    .disabled(isSavingMondayBoard)
                }
            }
        }
    }

    private func selectMondayBoard(_ board: MondayBoardSummary) {
        mondayBoardsError = nil
        isSavingMondayBoard = true
        Task {
            do {
                let response = try await CRMIntegrationManager.shared.selectMondayBoard(board: board)
                await MainActor.run {
                    applyMondayBoardSelection(board, response: response)
                    isSavingMondayBoard = false
                    showMondayBoardSheet = false
                    successMessage = "Monday board selected successfully."
                }
                await refreshMondayStatusIfNeeded()
                await loadIntegrations()
            } catch {
                await MainActor.run {
                    isSavingMondayBoard = false
                    mondayBoardsError = error.localizedDescription
                    errorMessage = mondayBoardsError
                }
            }
        }
    }
    
    private func loadCampaigns() async {
        do {
            campaigns = try await CampaignsAPI.shared.fetchCampaignsMetadata(workspaceId: WorkspaceContext.shared.workspaceId)
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
            let leads = try await FieldLeadsService.shared.fetchLeads(userId: userId, workspaceId: WorkspaceContext.shared.workspaceId, campaignId: campaignId)
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

    private func testButtonColor(for provider: IntegrationProvider) -> Color {
        switch provider {
        case .fub:
            return isFUBConnected ? .blue : .gray
        case .boldtrail:
            return isBoldTrailConnected ? .blue : .gray
        case .monday:
            return mondayIntegration?.isConnected == true ? .blue : .gray
        case .hubspot:
            return integrations.contains(where: { $0.provider == .hubspot && $0.isConnected }) ? .blue : .gray
        default:
            return .gray
        }
    }

    @MainActor
    private func refreshMondayStatusIfNeeded() async {
        guard integrations.contains(where: { $0.provider == .monday && $0.isConnected }) else { return }
        do {
            let status = try await CRMIntegrationManager.shared.fetchMondayStatus()
            applyMondayStatus(status)
        } catch {
            // Keep the table-backed integration state if the status refresh fails.
        }
    }

    @MainActor
    private func applyMondayBoardsResponse(_ response: MondayBoardsResponse) {
        integrations = integrations.map { integration in
            guard integration.provider == .monday else { return integration }
            return integration.updatingMondayConnection(
                selectedBoardId: response.selectedBoardId,
                selectedBoardName: response.selectedBoardName,
                accountId: response.accountId,
                accountName: response.accountName,
                replaceBoardSelection: true
            )
        }
    }

    @MainActor
    private func applyMondayStatus(_ status: MondayStatusResponse) {
        guard status.resolvedIsConnected != false else { return }
        integrations = integrations.map { integration in
            guard integration.provider == .monday else { return integration }
            return integration.updatingMondayConnection(
                selectedBoardId: status.selectedBoardId,
                selectedBoardName: status.selectedBoardName,
                accountId: status.accountId,
                accountName: status.accountName,
                workspaceId: status.workspaceId,
                workspaceName: status.workspaceName,
                replaceBoardSelection: true
            )
        }
    }

    @MainActor
    private func applyMondayBoardSelection(
        _ board: MondayBoardSummary,
        response: MondayBoardSelectionResponse
    ) {
        integrations = integrations.map { integration in
            guard integration.provider == .monday else { return integration }
            return integration.updatingMondayConnection(
                selectedBoardId: response.selectedBoardId ?? board.id,
                selectedBoardName: response.selectedBoardName ?? board.name,
                workspaceId: board.workspaceId,
                workspaceName: board.workspaceName,
                replaceBoardSelection: true
            )
        }
    }

    private func makeGenericTestLead(source: String, notes: String) -> LeadModel {
        let timestamp = Int(Date().timeIntervalSince1970)
        return LeadModel(
            name: "FLYR Test Lead",
            phone: "5555555555",
            email: "test+\(timestamp)@flyrpro.app",
            address: "123 Test St, Test City",
            source: source,
            notes: notes
        )
    }

    @MainActor
    private func sendTestLead(to provider: IntegrationProvider) async {
        testingProvider = provider
        errorMessage = nil
        successMessage = nil
        defer { testingProvider = nil }

        do {
            switch provider {
            case .fub:
                guard isFUBConnected else {
                    throw NSError(domain: "SyncSettingsView", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Follow Up Boss is not connected."
                    ])
                }
                let appointment = LeadSyncAppointment(
                    date: Date().addingTimeInterval(2 * 60 * 60),
                    title: "FLYR Test Appointment",
                    notes: "Test appointment from Sync Settings."
                )
                let task = LeadSyncTask(
                    title: "FLYR Test Follow Up",
                    dueDate: Date().addingTimeInterval(24 * 60 * 60)
                )
                let response = try await FUBPushLeadAPI.shared.pushLead(
                    makeGenericTestLead(
                        source: "FLYR iOS Follow Up Boss Test",
                        notes: "Test note from Sync Settings. Please verify notes sync."
                    ),
                    appointment: appointment,
                    task: task
                )
                let warningSuffix: String = {
                    guard let followUpErrors = response.followUpErrors, !followUpErrors.isEmpty else { return "" }
                    return " Some follow-up items reported issues."
                }()
                successMessage = "Test lead sent to Follow Up Boss.\(warningSuffix)"
            case .boldtrail:
                guard isBoldTrailConnected else {
                    throw NSError(domain: "SyncSettingsView", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "BoldTrail is not connected."
                    ])
                }
                _ = try await BoldTrailPushLeadAPI.shared.pushLead(
                    makeGenericTestLead(
                        source: "FLYR iOS BoldTrail Test",
                        notes: "Test lead from Sync Settings for BoldTrail / kvCORE."
                    )
                )
                successMessage = "Test lead sent to BoldTrail / kvCORE."
            case .monday:
                guard let userId = auth.user?.id else {
                    throw NSError(domain: "SyncSettingsView", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "You must be signed in to test Monday.com."
                    ])
                }
                successMessage = try await CRMIntegrationManager.shared.sendMondayTestLead(userId: userId)
            case .hubspot:
                guard integrations.contains(where: { $0.provider == .hubspot && $0.isConnected }) else {
                    throw NSError(domain: "SyncSettingsView", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "HubSpot is not connected."
                    ])
                }
                _ = try await CRMIntegrationManager.shared.testHubSpotConnection()
                let appointment = LeadSyncAppointment(
                    date: Date().addingTimeInterval(2 * 60 * 60),
                    title: "FLYR HubSpot Test Appointment",
                    notes: "Test appointment from Sync Settings."
                )
                let task = LeadSyncTask(
                    title: "FLYR HubSpot Test Follow Up",
                    dueDate: Date().addingTimeInterval(24 * 60 * 60)
                )
                let hubRes = try await HubSpotPushLeadAPI.shared.pushLead(
                    makeGenericTestLead(
                        source: "FLYR iOS HubSpot Test",
                        notes: "Test note from Sync Settings. Please verify notes sync."
                    ),
                    appointment: appointment,
                    task: task
                )
                var suffix = ""
                if let partial = hubRes.partialErrors, !partial.isEmpty {
                    suffix = " Some follow-up items reported issues."
                }
                successMessage = "Test lead sent to HubSpot.\(suffix)"
            default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SyncSettingsView()
}
