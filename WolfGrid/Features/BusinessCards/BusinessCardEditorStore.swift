import Foundation
import Combine

struct BusinessCardDraft: Codable, Equatable {
    var card: BusinessCardContent
    var published: Bool
}

@MainActor final class BusinessCardEditorStore: ObservableObject {
    // Reopening the editor shares the same writer, so an older request cannot
    // race a new editor and overwrite newer edits.
    private static var stores: [String: BusinessCardEditorStore] = [:]
    static func current() -> BusinessCardEditorStore {
        guard let workspace = WorkspaceContext.shared.workspaceId, let user = AuthManager.shared.user?.id else {
            return BusinessCardEditorStore(key: nil, read: { throw BusinessCardAPI.failure("Select a workspace and sign in first") }, write: { _ in })
        }
        let key = "business-card-draft.\(user.uuidString).\(workspace.uuidString)"
        if let store = stores[key] { return store }
        let store = BusinessCardEditorStore(key: key, read: {
            let result: BusinessCardProfileResponse = try await BusinessCardAPI.request("profile", workspaceID: workspace, expectedUserID: user)
            return BusinessCardDraft(card: result.profile?.content ?? BusinessCardContent(), published: result.profile?.published ?? false)
        }, write: { draft in
            var clean = draft.card
            clean.theme = clean.theme ?? .init()
            clean.socials.removeAll { $0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let content = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clean))
            let _: BusinessCardProfileResponse = try await BusinessCardAPI.request("profile", body: ["content": content, "published": draft.published], workspaceID: workspace, expectedUserID: user)
        })
        store.reconnect = NetworkMonitor.shared.$isOnline.removeDuplicates().dropFirst().sink { [weak store] online in
            if online { store?.flush() }
        }
        stores[key] = store
        return store
    }

    @Published var card = BusinessCardContent() { didSet { changed() } }
    var published: Bool { card.hasDetails }
    @Published private(set) var loaded = false
    @Published private(set) var isSaving = false
    @Published private(set) var status = "Loading…"
    @Published private(set) var canRetry = false
    private var reconnect: AnyCancellable?
    private var loading = false
    private var saved: BusinessCardDraft?
    private var debounce: Task<Void, Never>?
    private let key: String?
    private let defaults: UserDefaults
    private let read: () async throws -> BusinessCardDraft
    private let write: (BusinessCardDraft) async throws -> Void
    private let delay: UInt64
    private var draft: BusinessCardDraft { BusinessCardDraft(card: card, published: published) }

    init(key: String?, defaults: UserDefaults = .standard, delay: UInt64 = 650_000_000,
         read: @escaping () async throws -> BusinessCardDraft,
         write: @escaping (BusinessCardDraft) async throws -> Void) {
        self.key = key; self.defaults = defaults; self.delay = delay
        self.read = read; self.write = write
    }

    func load() async {
        if loaded { flush(); return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let local = key.flatMap { defaults.data(forKey: $0) }.flatMap { try? JSONDecoder().decode(BusinessCardDraft.self, from: $0) }
        do {
            var remote = try await read()
            addSocialSlots(to: &remote.card)
            saved = remote
            let initial = local ?? remote
            card = initial.card
            addSocialSlots(to: &card)
            loaded = true
            if draft != saved { changed() } else { status = published ? "All changes saved · Published" : "Add details to create your card" }
        } catch {
            if var local {
                addSocialSlots(to: &local.card)
                card = local.card; loaded = true
                status = "Saved on this iPhone · Waiting to sync"
            } else { status = "Couldn’t load your card. \(error.localizedDescription)" }
            canRetry = true
        }
    }

    private func addSocialSlots(to content: inout BusinessCardContent) {
        for platform in ["Instagram", "Facebook", "LinkedIn", "TikTok", "YouTube", "X", "Website"] where !content.socials.contains(where: { $0.platform == platform }) {
            content.socials.append(.init(platform: platform, url: ""))
        }
    }

    private func changed() {
        guard loaded else { return }
        // Persist every edit immediately; only network writes are debounced.
        if let key, let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: key) }
        debounce?.cancel()
        canRetry = false
        status = "Saving…"
        debounce = Task { [self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            debounce = nil
            await savePending()
        }
    }

    func flush() {
        debounce?.cancel()
        debounce = nil
        Task { [self] in
            if !loaded { await load() } else { await savePending() }
        }
    }

    /// Sharing must wait for publication, including a saved card from an older app.
    func prepareForSharing() async throws {
        while loading { try await Task.sleep(nanoseconds: 20_000_000) }
        if !loaded { await load() }
        guard loaded else { throw BusinessCardAPI.failure(status) }
        guard card.hasDetails else { throw BusinessCardAPI.failure("Add your business card details first") }
        debounce?.cancel()
        debounce = nil
        while isSaving { try await Task.sleep(nanoseconds: 20_000_000) }
        try Task.checkCancellation()
        await savePending()
        guard saved == draft, saved?.published == true else {
            throw BusinessCardAPI.failure(status)
        }
    }

    private func savePending() async {
        guard loaded, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        while draft != saved {
            let snapshot = draft
            if let issue = validationIssue(snapshot.card) {
                status = "Saved on this iPhone · \(issue)"
                canRetry = false
                return
            }
            status = "Saving…"
            do {
                try await write(snapshot)
                saved = snapshot
            } catch {
                status = "Saved on this iPhone · Couldn’t sync. Retry when connected."
                canRetry = true
                return
            }
            // If edits arrived during the request, loop with the newest snapshot.
        }
        if let key { defaults.removeObject(forKey: key) }
        canRetry = false
        status = published ? "All changes saved · Published" : "Add details to create your card"
    }

    private func validationIssue(_ content: BusinessCardContent) -> String? {
        if !content.email.isEmpty && !content.email.contains("@") { return "Finish your email to sync" }
        let links = [("photo link", content.photo), ("logo link", content.companyLogo ?? ""), ("review link", content.reviewUrl)] + content.socials.map { ($0.platform + " link", $0.url) }
        for (label, value) in links where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                return "Finish your \(label) with https:// to sync"
            }
        }
        return nil
    }
}
