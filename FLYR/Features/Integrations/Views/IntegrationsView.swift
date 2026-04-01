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
    @State private var showConnectBoldTrail = false
    @State private var apiKeyProvider: IntegrationProvider?
    @State private var webhookProvider: IntegrationProvider?
    @State private var apiKeyText = ""
    @State private var webhookURLText = ""
    @State private var isConnectingAPIKey = false
    @State private var isConnectingWebhook = false
    @State private var apiKeyError: String?
    @State private var webhookError: String?
    @State private var fubActionMessage: String?
    @State private var fubActionSuccess: Bool = true
    @State private var isFUBActionInProgress = false
    @State private var showMondayBoardSheet = false
    @State private var mondayBoards: [MondayBoardSummary] = []
    @State private var isLoadingMondayBoards = false
    @State private var isSavingMondayBoard = false
    @State private var mondayBoardsError: String?
    @State private var hubSpotActionMessage: String?
    @State private var hubSpotActionSuccess: Bool = true
    @State private var isHubSpotActionInProgress = false

    private var fubIntegration: UserIntegration? {
        integrations.first { $0.provider == .fub }
    }

    private var mondayIntegration: UserIntegration? {
        integrations.first { $0.provider == .monday }
    }

    private var hubspotIntegration: UserIntegration? {
        integrations.first { $0.provider == .hubspot }
    }

    private var isFUBConnected: Bool {
        crmStore.isFUBConnected || (fubIntegration?.isConnected == true)
    }

    private var isBoldTrailConnected: Bool {
        crmStore.boldtrailConnection?.isConnected == true
    }

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
                                    ForEach([IntegrationProvider.fub, .boldtrail, .hubspot, .monday], id: \.id) { provider in
                                        let integration = integrations.first { $0.provider == provider }
                                        let crmConnection: CRMConnection? = {
                                            switch provider {
                                            case .fub:
                                                return crmStore.fubConnection
                                            case .boldtrail:
                                                return crmStore.boldtrailConnection
                                            default:
                                                return nil
                                            }
                                        }()
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

                            if let mondayIntegration, mondayIntegration.isConnected {
                                Section {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(mondayIntegration.mondayNeedsBoardSelection
                                             ? "Monday.com is connected, but FLYR still needs a board before sync can run."
                                             : "FLYR will sync leads to \(mondayIntegration.selectedBoardName ?? "your selected monday board").")
                                            .font(.system(size: 14))
                                            .foregroundColor(.muted)

                                        if let mondayBoardsError, !showMondayBoardSheet {
                                            Text(mondayBoardsError)
                                                .font(.system(size: 13))
                                                .foregroundColor(.error)
                                        }

                                        Button(action: { presentMondayBoardPicker() }) {
                                            HStack(spacing: 8) {
                                                if isLoadingMondayBoards || isSavingMondayBoard {
                                                    ProgressView()
                                                        .tint(.white)
                                                }
                                                Text(mondayIntegration.mondayNeedsBoardSelection ? "Select Board" : "Change Board")
                                                    .font(.system(size: 15, weight: .medium))
                                            }
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(mondayIntegration.mondayNeedsBoardSelection ? Color.info : Color.accent)
                                            .cornerRadius(10)
                                        }
                                        .disabled(isLoadingMondayBoards || isSavingMondayBoard)
                                    }
                                    .padding(16)
                                    .background(Color.bgSecondary)
                                    .cornerRadius(20)
                                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                                } header: {
                                    HStack {
                                        Text("Monday.com")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundColor(.text)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }

                            // HubSpot actions (when connected)
                            if let hubspotIntegration, hubspotIntegration.isConnected {
                                Section {
                                    VStack(spacing: 12) {
                                        if let msg = hubSpotActionMessage {
                                            Text(msg)
                                                .font(.system(size: 13))
                                                .foregroundColor(hubSpotActionSuccess ? .success : .error)
                                                .multilineTextAlignment(.center)
                                        }
                                        Button(action: { runHubSpotTestConnection() }) {
                                            HStack(spacing: 6) {
                                                if isHubSpotActionInProgress { ProgressView().scaleEffect(0.8).tint(.white) }
                                                Text("Test connection")
                                                    .font(.system(size: 15, weight: .medium))
                                            }
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.info)
                                            .cornerRadius(10)
                                        }
                                        .disabled(isHubSpotActionInProgress)
                                    }
                                    .padding(16)
                                    .background(Color.bgSecondary)
                                    .cornerRadius(20)
                                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                                } header: {
                                    HStack {
                                        Text("HubSpot")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundColor(.text)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }

                            // Follow Up Boss actions (when connected)
                            if isFUBConnected {
                                Section {
                                    VStack(spacing: 12) {
                                        if let msg = fubActionMessage {
                                            Text(msg)
                                                .font(.system(size: 13))
                                                .foregroundColor(fubActionSuccess ? .success : .error)
                                                .multilineTextAlignment(.center)
                                        }
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
            .sheet(isPresented: $showAPIKeySheet) {
                apiKeyInputSheet
            }
            .sheet(isPresented: $showWebhookSheet) {
                webhookInputSheet
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
                        handleDisconnect(provider: .fub)
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
                        }
                    },
                    onCancel: { showConnectBoldTrail = false },
                    onDisconnect: isBoldTrailConnected ? {
                        handleDisconnect(provider: .boldtrail)
                    } : nil
                )
            }
            .sheet(isPresented: $showMondayBoardSheet) {
                mondayBoardPickerSheet
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
        if provider == .boldtrail {
            showConnectBoldTrail = true
            return
        }
        switch provider.connectionType {
        case .oauth:
            oauthProvider = provider
            showOAuth = true
        case .token:
            showConnectBoldTrail = true
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
        if provider == .boldtrail {
            Task {
                do {
                    try await BoldTrailConnectAPI.shared.disconnect()
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
    
    @MainActor
    private func loadIntegrations() async {
        guard let userId = auth.user?.id else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let integrationsTask = CRMIntegrationManager.shared.fetchIntegrations(userId: userId)
            async let crmTask: Void = CRMConnectionStore.shared.refresh(userId: userId)
            integrations = try await integrationsTask
            await crmTask
            await refreshMondayStatusIfNeeded()
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
    
    private func runHubSpotTestConnection() {
        hubSpotActionMessage = nil
        isHubSpotActionInProgress = true
        Task {
            do {
                let msg = try await CRMIntegrationManager.shared.testHubSpotConnection()
                await MainActor.run {
                    isHubSpotActionInProgress = false
                    hubSpotActionSuccess = true
                    hubSpotActionMessage = msg
                }
            } catch {
                await MainActor.run {
                    isHubSpotActionInProgress = false
                    hubSpotActionSuccess = false
                    hubSpotActionMessage = error.localizedDescription
                }
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
                } else {
                    ForEach(mondayBoards) { board in
                        Button(action: {
                            selectMondayBoard(board)
                        }) {
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
                    throw NSError(
                        domain: "IntegrationsView",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Use the Follow Up Boss Connect flow."]
                    )
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
        guard webhookProvider != nil,
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

    @MainActor
    private func refreshMondayStatusIfNeeded() async {
        guard integrations.contains(where: { $0.provider == .monday && $0.isConnected }) else { return }
        do {
            let status = try await CRMIntegrationManager.shared.fetchMondayStatus()
            applyMondayStatus(status)
        } catch {
            // Keep the existing integration snapshot if status refresh fails.
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
}

// MARK: - Preview

#Preview {
    IntegrationsView()
}
