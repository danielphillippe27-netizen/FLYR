import SwiftUI
import Supabase

struct FieldSalesWorkspaceSettings: View {
    @ObservedObject private var context = WorkspaceContext.shared
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        if let workspace = context.workspaceId, let user = auth.user?.id {
            FieldSalesWorkspaceSettingContent(workspace: workspace).id("\(user):\(workspace)")
        }
    }
}

private struct FieldSalesWorkspaceSettingContent: View {
    let workspace: UUID
    @Environment(\.scenePhase) private var scene
    @State private var setting: Setting?
    @State private var saving = false
    @State private var error: String?

    private struct Setting: Decodable {
        let enabled: Bool
        let can_manage: Bool
        let needs_setup: Bool
    }

    private struct Params: Encodable {
        let p_workspace: UUID
        var p_enabled: Bool?
    }

    var body: some View {
        Group {
            if let setting, setting.can_manage {
                Section {
                    Toggle("Sales", isOn: Binding(get: { setting.enabled }, set: { enabled in
                        Task { await load(enabled) }
                    }))
                    .disabled(saving)
                    if setting.needs_setup {
                        NavigationLink("Set reporting currency and timezone") { FieldSalesRootView() }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                } footer: {
                    Text("Show Sales across this workspace. On by default for roofing.")
                }
            } else if error != nil {
                Button("Retry loading Sales settings") { Task { await load() } }
            }
        }
        .task(id: scene) { if scene == .active { await load() } }
    }

    private func load(_ enabled: Bool? = nil) async {
        guard !saving else { return }
        if enabled != nil { saving = true }
        defer { if enabled != nil { saving = false } }
        error = nil
        do {
            let updated: Setting = try await SupabaseManager.shared.client
                .rpc("field_sales_workspace_command", params: Params(p_workspace: workspace, p_enabled: enabled))
                .execute().value
            guard !Task.isCancelled else { return }
            setting = updated
            if enabled != nil { NotificationCenter.default.post(name: .fieldSalesChanged, object: nil) }
        } catch {
            if !Task.isCancelled { self.error = "Couldn't refresh Sales settings." }
        }
    }
}

struct FieldSessionSales: View {
    let sessionID: UUID
    @ObservedObject private var context = WorkspaceContext.shared
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        if let workspace = context.workspaceId, let user = auth.user?.id {
            FieldSessionSalesContent(workspace: workspace, sessionID: sessionID)
                .id("\(user):\(workspace):\(sessionID)")
        }
    }
}

private struct FieldSessionSalesContent: View {
    let workspace: UUID
    let sessionID: UUID
    @Environment(\.scenePhase) private var scene
    @State private var revision = 0
    @State private var summary: Summary?

    private struct Summary: Decodable {
        let enabled: Bool
        let verified_sales: Int?
        let appointments_set: Int?
        let appointments_closed: Int?
        let currency: String?
        let value_minor: String?
        let value_scope: String?
    }

    private struct Params: Encodable {
        let p_workspace: UUID
        let p_session: UUID
    }

    var body: some View {
        Group {
            if let summary, summary.enabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Sales").font(.headline)
                    LabeledContent("Appointments set", value: String(summary.appointments_set ?? 0))
                    LabeledContent("Appointments closed", value: String(summary.appointments_closed ?? 0))
                    LabeledContent("Verified sales", value: String(summary.verified_sales ?? 0))
                    if let value = summary.value_minor, let currency = summary.currency {
                        LabeledContent(summary.value_scope == "self" ? "Credited contract value" : "Verified contract value",
                                       value: FieldSalesService.money(value, currency: currency))
                    }
                }
                .font(.subheadline)
                .padding(16)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .task(id: revision) {
            let updated: Summary? = try? await SupabaseManager.shared.client
                .rpc("field_sales_session_summary", params: Params(p_workspace: workspace, p_session: sessionID))
                .execute().value
            if !Task.isCancelled { summary = updated }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in revision += 1 }
        .onChange(of: scene) { _, phase in if phase == .active { revision += 1 } }
    }
}
