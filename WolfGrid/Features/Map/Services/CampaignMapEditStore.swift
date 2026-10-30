import Foundation
import Combine
import CryptoKit
import Supabase

/// A durable, account-scoped edit journal. A command is written to disk before
/// it becomes visible. Batches and undo replay through one revision-aware API.
@MainActor
final class CampaignMapEditStore: ObservableObject {
    typealias Transport = (String, CampaignMapEditRequest?) async throws -> (CampaignMapEditState, Int)
    static let shared = CampaignMapEditStore()
    @Published private(set) var generation = 0
    private(set) var savedGeneration = 0
    private(set) var geometryGeneration = 0
    @Published private(set) var issues: [String: String] = [:]
    private let root: URL
    private let transport: Transport
    private let scopeProvider: ((String) -> String?)?
    private var archives: [String: CampaignMapEditArchive] = [:]
    private var campaignByScope: [String: String] = [:]
    private var syncing: Set<String> = []
    private var conflicts: Set<String> = []
    private var loadFailures: Set<String> = []
    private var snapshotCache: [String: (String, CampaignMapEditSnapshot)] = [:]
    private var previews: [String: [CampaignMapEditChange]] = [:]
    private var networkObserver: AnyCancellable?

    init(root: URL? = nil, scopeProvider: ((String) -> String?)? = nil, transport: Transport? = nil, observeNetwork: Bool = true) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CampaignMapEdits", isDirectory: true)
        self.scopeProvider = scopeProvider
        self.transport = transport ?? Self.remote
        if observeNetwork {
            networkObserver = NetworkMonitor.shared.$isOnline.removeDuplicates().sink { [weak self] online in
                guard online else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for campaign in Set(self.campaignByScope.values) { await self.synchronize(campaign) }
                }
            }
        }
    }
    private func scope(_ campaign: String) -> String? {
        if let scopeProvider { return scopeProvider(campaign) }
        guard let user = AuthManager.shared.user?.id else { return nil }
        return "\(user.uuidString.lowercased())|\(WorkspaceContext.shared.workspaceId?.uuidString.lowercased() ?? "personal")|\(campaign.lowercased())"
    }
    private func file(_ key: String) -> URL {
        root.appendingPathComponent(SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".json")
    }
    private func load(_ campaign: String) throws -> (String, CampaignMapEditArchive) {
        guard let key = scope(campaign) else { throw CampaignMapEditError.unavailable("Sign in before editing the map.") }
        if loadFailures.contains(key) { throw CampaignMapEditError.unavailable("Saved corrections could not be read. They have been kept on this device.") }
        if let archive = archives[key] { return (key, archive) }
        do {
            let url = file(key)
            let archive = FileManager.default.fileExists(atPath: url.path) ? try JSONDecoder().decode(CampaignMapEditArchive.self, from: Data(contentsOf: url)) : CampaignMapEditArchive()
            archives[key] = archive; campaignByScope[key] = campaign
            return (key, archive)
        } catch {
            loadFailures.insert(key); issues[key] = error.localizedDescription
            throw CampaignMapEditError.unavailable("Saved corrections could not be read. They have been kept on this device.")
        }
    }
    private func save(_ archive: CampaignMapEditArchive, key: String) throws {
        var durable = archive
        durable.scope = key; durable.campaignId = campaignByScope[key]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(durable).write(to: file(key), options: .atomic)
        let geometryChanged = archives[key]?.effective.features != durable.effective.features
        archives[key] = durable
        if geometryChanged {
            snapshotCache.removeValue(forKey: key)
            geometryGeneration &+= 1
        }
        savedGeneration &+= 1
        generation &+= 1
    }
    func resumePending() async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "json" {
            guard let bytes = try? Data(contentsOf: url),
                  let saved = try? JSONDecoder().decode(CampaignMapEditArchive.self, from: bytes),
                  let campaign = saved.campaignId, let key = saved.scope,
                  scope(campaign) == key, url.lastPathComponent == file(key).lastPathComponent else { continue }
            if archives[key] == nil { archives[key] = saved; campaignByScope[key] = campaign }
            if !saved.pending.isEmpty { await synchronize(campaign) }
        }
    }
    func storedState(for campaign: String) -> CampaignMapEditState { (try? load(campaign).1.effective) ?? CampaignMapEditState() }
    func state(for campaign: String) -> CampaignMapEditState {
        let state = storedState(for: campaign)
        return scope(campaign).flatMap { previews[$0] }.map { state.applying($0) } ?? state
    }
    func preview(_ campaign: String, changes: [CampaignMapEditChange]?) {
        guard let key = scope(campaign) else { return }
        guard previews[key] != changes else { return }
        previews[key] = changes
        snapshotCache.removeValue(forKey: key)
        geometryGeneration &+= 1
        generation &+= 1
    }
    func hasEdits(_ campaign: String) -> Bool { !state(for: campaign).features.isEmpty }
    func pendingCount(_ campaign: String) -> Int { (try? load(campaign).1.pending.count) ?? 0 }
    func hasConflict(_ campaign: String) -> Bool { scope(campaign).map { conflicts.contains($0) } ?? false }
    func issue(_ campaign: String) -> String? { scope(campaign).flatMap { issues[$0] } }
    func canUndo(_ campaign: String) -> Bool { (try? load(campaign).1.history.isEmpty == false) ?? false }
    func status(_ campaign: String) -> String {
        if hasConflict(campaign) { return "Review teammate changes" }
        if issue(campaign) != nil { return "Saved on device · Sync needs attention" }
        if pendingCount(campaign) > 0 { return "Saved on device · Pending sync" }
        return "Saved"
    }
    func snapshot(campaign: String, signature: String, buildings: [BuildingFeature], addresses: [AddressFeature], parcels: [ParcelFeature]) -> CampaignMapEditSnapshot {
        guard let key = scope(campaign) else { return .init(buildings: buildings, addresses: addresses, parcels: parcels) }
        if let (cachedSignature, snapshot) = snapshotCache[key], cachedSignature == signature { return snapshot }
        let result = CampaignMapEdits.snapshot(buildings: buildings, addresses: addresses, parcels: parcels, state: state(for: campaign))
        snapshotCache[key] = (signature, result)
        return result
    }
    func commit(_ campaign: String, title: String, changes: [CampaignMapEditChange], startSync: Bool = true) throws {
        guard !changes.isEmpty, changes.count <= 500, Set(changes.map { $0.item.id }).count == changes.count,
              changes.allSatisfy({ change in
                  !change.id.isEmpty && change.id.count <= 256 &&
                  (change.value?.geometry.map { CampaignMapEdits.validGeometry($0, for: change.kind) } ?? true)
              }) else { throw CampaignMapEditError.invalidSelection }
        var (key, archive) = try load(campaign)
        guard !conflicts.contains(key) else { throw CampaignMapEditError.conflict }
        let effective = archive.effective
        let command = CampaignMapEditCommand(request: .init(clientMutationId: UUID().uuidString.lowercased(),
            baseRevision: archive.server.revision + archive.pending.count, changes: changes), title: title,
            previous: changes.map { .init($0.item, value: effective.features[$0.item.id]) })
        archive.pending.append(command)
        archive.history.append(command)
        archive.history = Array(archive.history.suffix(30))
        try save(archive, key: key)
        previews[key] = nil
        if startSync { Task { await synchronize(campaign) } }
    }
    func undo(_ campaign: String, startSync: Bool = true) throws {
        var (key, archive) = try load(campaign)
        guard !conflicts.contains(key) else { throw CampaignMapEditError.conflict }
        guard let command = archive.history.last else { return }
        let effective = archive.effective
        guard command.request.changes.allSatisfy({ effective.features[$0.item.id] == $0.value }) else { throw CampaignMapEditError.changedSinceUndo }
        archive.history.removeLast()
        // Keep the original and its inverse in order, even offline. Reusing a
        // mutation ID or dropping an in-flight edit would lose a committed undo.
        archive.pending.append(.init(request: .init(clientMutationId: UUID().uuidString.lowercased(),
            baseRevision: archive.server.revision + archive.pending.count, changes: command.previous),
            title: "Undo \(command.title)", previous: command.request.changes))
        try save(archive, key: key)
        if startSync { Task { await synchronize(campaign) } }
    }
    func recordCreation(_ campaign: String, items: [CampaignMapItem]) throws {
        guard !items.isEmpty else { return }
        var (key, archive) = try load(campaign)
        let current = archive.effective
        let changes = items.map { CampaignMapEditChange($0, value: current.features[$0.id]) }
        let previous = items.map { item -> CampaignMapEditChange in
            var hidden = current.features[item.id] ?? CampaignMapEditValue()
            hidden.hidden = true
            return .init(item, value: hidden)
        }
        // Creation already uses the durable manual-address queue. Undo hides
        // the newly created map items without deleting any captured history.
        archive.history.append(.init(request: .init(clientMutationId: UUID().uuidString.lowercased(),
            baseRevision: archive.server.revision + archive.pending.count, changes: changes), title: "Add house", previous: previous))
        archive.history = Array(archive.history.suffix(30))
        try save(archive, key: key)
    }
    func synchronize(_ campaign: String) async {
        guard let (key, initial) = try? load(campaign), !syncing.contains(key), !conflicts.contains(key) else { return }
        if scopeProvider == nil && !NetworkMonitor.shared.isOnline { return }
        syncing.insert(key)
        defer { syncing.remove(key) }
        do {
            if initial.pending.isEmpty {
                let (state, status) = try await transport(campaign, nil)
                guard scope(campaign) == key else { return }
                guard status == 200 else { throw CampaignMapEditError.unavailable("Map corrections are unavailable. Tap Retry when connected.") }
                var latest = archives[key] ?? initial
                if latest.server != state {
                    latest.server = state
                    try save(latest, key: key)
                }
            }
            var rebases = 0
            while scope(campaign) == key, let first = archives[key]?.pending.first {
                let (server, status) = try await transport(campaign, first.request)
                guard scope(campaign) == key, var latest = archives[key] else { return }
                if status == 409 {
                    latest.server = server
                    let unchanged = first.previous.allSatisfy { server.features[$0.item.id] == $0.value }
                    if !unchanged || rebases >= 3 {
                        try save(latest, key: key)
                        conflicts.insert(key); issues[key] = CampaignMapEditError.conflict.localizedDescription
                        return
                    }
                    latest.pending[0].request.baseRevision = server.revision
                    try save(latest, key: key)
                    rebases += 1
                    continue
                }
                guard status == 200 else { throw CampaignMapEditError.unavailable("Your corrections are saved on this device. Sync will retry when available.") }
                latest.server = server
                latest.pending.removeFirst()
                try save(latest, key: key)
                rebases = 0
            }
            issues[key] = nil
        } catch { issues[key] = error.localizedDescription }
    }
    /// Explicit conflict choices keep queued work durable until the user decides.
    func resolveConflict(_ campaign: String, keepMine: Bool) throws {
        var (key, archive) = try load(campaign)
        guard conflicts.contains(key), let first = archive.pending.first else { return }
        if keepMine {
            let replacement = CampaignMapEditCommand(request: .init(clientMutationId: UUID().uuidString.lowercased(),
                baseRevision: archive.server.revision, changes: first.request.changes), title: first.title,
                previous: first.request.changes.map { .init($0.item, value: archive.server.features[$0.item.id]) })
            archive.pending[0] = replacement
            // Earlier undo entries describe the old shared state.
            archive.history = [replacement]
        } else {
            // Dependent later commands may refer to the conflicted edit. Keep
            // the server state as one coherent choice rather than replaying them.
            archive.pending.removeAll(); archive.history.removeAll()
        }
        try save(archive, key: key)
        conflicts.remove(key); issues[key] = nil
        Task { await synchronize(campaign) }
    }
    private static func remote(_ campaign: String, request: CampaignMapEditRequest?) async throws -> (CampaignMapEditState, Int) {
        let session = try await SupabaseManager.shared.client.auth.session
        let base = Config.backendAPIURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/campaigns/\(campaign)/map-edits") else { throw URLError(.badURL) }
        var http = URLRequest(url: url)
        http.httpMethod = request == nil ? "GET" : "POST"
        http.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.timeoutInterval = 30
        if let request { http.httpBody = try JSONEncoder().encode(request) }
        let (data, response) = try await URLSession.shared.data(for: http)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard status == 200 || status == 409 else {
            let message = status == 401 ? "Sign in again to sync your saved map corrections." :
                status == 403 ? "You no longer have permission to edit this campaign. Your corrections are kept on this device." :
                "Your map corrections are saved on this device. Sync will retry when the service is available."
            throw CampaignMapEditError.unavailable(message)
        }
        return (try JSONDecoder().decode(CampaignMapEditState.self, from: data), status)
    }
}
