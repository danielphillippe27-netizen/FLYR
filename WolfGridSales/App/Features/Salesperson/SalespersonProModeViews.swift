import Auth
import Combine
import Foundation
import Supabase
import SwiftUI

private struct ProPipelineStage: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let color: String
    let position: Int
    let terminalKind: String?
    let isArchived: Bool
}

private struct ProPipelineLead: Codable, Identifiable {
    let id: UUID
    let name: String
    let company: String?
    let email: String?
    let phone: String?
    let pipelineStageId: UUID?
    let nextTaskTitle: String?
    let nextFollowUpAt: Date?
    let lastTouchSummary: String?
}

private struct ProStagesResponse: Decodable { let stages: [ProPipelineStage] }
private struct ProPipelineResponse: Decodable { let leads: [ProPipelineLead] }

private actor SalespersonProAPI {
    static let shared = SalespersonProAPI()

    func stages() async throws -> [ProPipelineStage] {
        let response: ProStagesResponse = try await request(path: "/api/pipeline/stages", method: "GET", body: Optional<String>.none)
        return response.stages.filter { !$0.isArchived }.sorted { $0.position < $1.position }
    }

    func leads() async throws -> [ProPipelineLead] {
        let response: ProPipelineResponse = try await request(path: "/api/salesperson/pipeline", method: "GET", body: Optional<String>.none)
        return response.leads
    }

    func move(leadID: UUID, stageID: UUID) async throws {
        struct Move: Encodable { let pipelineStageId: UUID }
        struct Response: Decodable { let lead: ProPipelineLead? }
        let _: Response = try await request(path: "/api/salesperson/pipeline/\(leadID.uuidString)", method: "PATCH", body: Move(pipelineStageId: stageID))
    }

    private func request<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body?) async throws -> Response {
        let session = try await SupabaseManager.shared.client.auth.session
        guard let url = URL(string: path, relativeTo: Config.backendAPIURL)?.absoluteURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.proMode.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "WolfGridPro", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message ?? "WolfGrid request failed."])
        }
        return try JSONDecoder.proMode.decode(Response.self, from: data)
    }
}

@MainActor
private final class SalespersonPipelineModel: ObservableObject {
    @Published var stages: [ProPipelineStage] = []
    @Published var leads: [ProPipelineLead] = []
    @Published var loading = false
    @Published var error: String?

    private struct PendingMove: Codable { let leadID: UUID; let stageID: UUID }
    private let stagesCacheKey = "wolfgrid.pro.pipeline.stages"
    private let leadsCacheKey = "wolfgrid.pro.pipeline.leads"
    private let movesCacheKey = "wolfgrid.pro.pipeline.pendingMoves"

    init() {
        let decoder = JSONDecoder.proMode
        if let data = UserDefaults.standard.data(forKey: stagesCacheKey) { stages = (try? decoder.decode([ProPipelineStage].self, from: data)) ?? [] }
        if let data = UserDefaults.standard.data(forKey: leadsCacheKey) { leads = (try? decoder.decode([ProPipelineLead].self, from: data)) ?? [] }
    }

    func refresh() async {
        loading = true
        do {
            await flushPendingMoves()
            async let stages = SalespersonProAPI.shared.stages()
            async let leads = SalespersonProAPI.shared.leads()
            self.stages = try await stages
            self.leads = try await leads
            saveCache()
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    func move(_ lead: ProPipelineLead, to stage: ProPipelineStage) async {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            let current = leads[index]
            leads[index] = ProPipelineLead(id: current.id, name: current.name, company: current.company, email: current.email, phone: current.phone, pipelineStageId: stage.id, nextTaskTitle: current.nextTaskTitle, nextFollowUpAt: current.nextFollowUpAt, lastTouchSummary: current.lastTouchSummary)
            saveCache()
        }
        do {
            try await SalespersonProAPI.shared.move(leadID: lead.id, stageID: stage.id)
            await refresh()
        } catch {
            var pending = pendingMoves
            pending.removeAll { $0.leadID == lead.id }
            pending.append(PendingMove(leadID: lead.id, stageID: stage.id))
            savePending(pending)
            self.error = "Saved offline. WolfGrid will sync this pipeline move when the connection returns."
        }
    }

    private var pendingMoves: [PendingMove] {
        guard let data = UserDefaults.standard.data(forKey: movesCacheKey) else { return [] }
        return (try? JSONDecoder.proMode.decode([PendingMove].self, from: data)) ?? []
    }

    private func flushPendingMoves() async {
        var remaining: [PendingMove] = []
        for move in pendingMoves {
            do { try await SalespersonProAPI.shared.move(leadID: move.leadID, stageID: move.stageID) }
            catch { remaining.append(move) }
        }
        savePending(remaining)
    }

    private func saveCache() {
        let encoder = JSONEncoder.proMode
        UserDefaults.standard.set(try? encoder.encode(stages), forKey: stagesCacheKey)
        UserDefaults.standard.set(try? encoder.encode(leads), forKey: leadsCacheKey)
    }

    private func savePending(_ moves: [PendingMove]) {
        UserDefaults.standard.set(try? JSONEncoder.proMode.encode(moves), forKey: movesCacheKey)
    }
}

struct SalespersonPipelineView: View {
    @StateObject private var model = SalespersonPipelineModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.loading && model.stages.isEmpty { ProgressView("Loading pipeline…") }
                else if model.stages.isEmpty { ContentUnavailableView("No pipeline stages", systemImage: "rectangle.3.group", description: Text("An admin can configure stages in WolfGrid Sales.")) }
                else { board }
            }
            .navigationTitle("Pipeline")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") } } }
            .task { await model.refresh() }
            .refreshable { await model.refresh() }
            .alert("Pipeline", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") {} } message: { Text(model.error ?? "") }
        }
    }

    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(model.stages) { stage in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Circle().fill(Color(hex: stage.color)).frame(width: 9, height: 9)
                            Text(stage.name).font(.headline)
                            Spacer()
                            Text("\(model.leads.filter { $0.pipelineStageId == stage.id }.count)").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                        ForEach(model.leads.filter { $0.pipelineStageId == stage.id }) { lead in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(lead.name).font(.body.weight(.semibold))
                                Text(lead.company ?? lead.email ?? lead.phone ?? "No contact details").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Label(lead.nextTaskTitle ?? "No next action", systemImage: lead.nextTaskTitle == nil ? "exclamationmark.triangle" : "checkmark.circle").font(.caption).foregroundStyle(lead.nextTaskTitle == nil ? .orange : .secondary)
                                Menu("Move") { ForEach(model.stages.filter { $0.id != stage.id }) { target in Button(target.name) { Task { await model.move(lead, to: target) } } } }
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(12).frame(width: 260, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12).frame(width: 284, alignment: .top)
                    .background(Color(uiColor: .systemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding()
        }
    }
}

struct SalespersonFollowUpHubView: View {
    var body: some View {
        SalespersonTasksView()
    }
}

private extension JSONEncoder {
    static var proMode: JSONEncoder { let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.dateEncodingStrategy = .iso8601; return encoder }
}

private extension JSONDecoder {
    static var proMode: JSONDecoder { let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; decoder.dateDecodingStrategy = .iso8601; return decoder }
}
