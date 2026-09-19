import Foundation
import Combine
import Supabase

@MainActor final class WolfyEconomyStore: ObservableObject {
    @Published var celebration: WolfyReward?
    @Published var snapshot: WolfySnapshot? {
        didSet {
            if let snapshot, let data=try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data,forKey:"wolfy.snapshot.\(workspace).\(user)")
            }
        }
    }
    @Published var error: String?
    @Published var busy = false
    let user: UUID
    let workspace: UUID
    private let client = SupabaseManager.shared.client
    private var cacheKey: String { "wolfy.equipment.\(workspace).\(user)" }
    init(user: UUID, workspace: UUID) {
        self.user = user; self.workspace = workspace
        if let data=UserDefaults.standard.data(forKey:"wolfy.snapshot.\(workspace).\(user)") {
            snapshot=try? JSONDecoder().decode(WolfySnapshot.self,from:data)
        }
    }
    var effectiveEquipment: [String:String] {
        var result=snapshot?.equipped ?? [:]
        for (id,enabled) in UserDefaults.standard.dictionary(forKey:cacheKey) as? [String:Bool] ?? [:] {
            guard let item=snapshot?.catalog?.first(where:{$0.id==id}),snapshot?.owned.contains(id)==true else { continue }
            if enabled { result[item.category]=id } else if result[item.category]==id { result.removeValue(forKey:item.category) }
        }
        return result
    }
    func settings(start:Int,end:Int,dnd:Bool) async throws {
        struct Params:Encodable { let p_workspace:UUID;let p_user:UUID;let p_start:Int;let p_end:Int;let p_dnd:Bool;let p_timezone:String }
        try await client.rpc("wolfy_settings",params:Params(p_workspace:workspace,p_user:user,p_start:start,p_end:end,p_dnd:dnd,p_timezone:TimeZone.current.identifier)).execute()
        await refresh()
    }
    private struct Scope: Encodable { let p_workspace: UUID; let p_user: UUID; let p_timezone=TimeZone.current.identifier }
    func refresh() async {
        do {
            snapshot = try await client.rpc("wolfy_snapshot", params: Scope(p_workspace: workspace,p_user: user)).execute().value
            let key="wolfy.lastReward.\(workspace).\(user)"
            if let reward=snapshot?.rewards?.first {
                if let previous=UserDefaults.standard.string(forKey:key), previous != reward.id {
                    let oldLevel=UserDefaults.standard.integer(forKey:key+".level")
                    let newLevel=WolfyProgression.level(xp:snapshot?.profile.xp ?? 0)
                    if oldLevel>0 && WolfyProgression.rank(level:oldLevel) != WolfyProgression.rank(level:newLevel) {
                        celebration=WolfyReward(id:reward.id+".rank",source_event:"rank_up")
                    } else if oldLevel>0 && newLevel>oldLevel {
                        celebration=WolfyReward(id:reward.id+".level",source_event:"level_up")
                    } else { celebration=reward }
                }
                UserDefaults.standard.set(WolfyProgression.level(xp:snapshot?.profile.xp ?? 0),forKey:key+".level")
                UserDefaults.standard.set(reward.id,forKey:key)
            }
            error = nil
            await flushEquipment()
        } catch { self.error = "Wolfy progression is unavailable. Your Home activity remains accessible." }
    }
    func purchase(_ item: WolfyCatalogItem, request: UUID) async throws {
        guard NetworkMonitor.shared.isOnline else { throw failure("Connect to purchase an item.") }
        struct Params: Encodable { let p_workspace: UUID; let p_user: UUID; let p_item: String; let p_request: UUID }
        let rpc = item.render_kind == "portrait" ? "wolfy_purchase_portrait" : "wolfy_purchase"
        snapshot = try await client.rpc(rpc,params: Params(p_workspace: workspace,p_user: user,p_item: item.id,p_request: request)).execute().value
        error = nil
    }
    func equip(_ item: WolfyCatalogItem, enabled: Bool) async throws {
        guard snapshot?.owned.contains(item.id) == true else { throw failure("This item is not owned.") }
        // Only queue previously confirmed ownership; the server rechecks it on replay.
        if !NetworkMonitor.shared.isOnline {
            var pending = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Bool] ?? [:]
            if enabled {
                pending=pending.filter { id,_ in snapshot?.catalog?.first(where:{$0.id==id})?.category != item.category }
            }
            pending[item.id] = enabled
            UserDefaults.standard.set(pending, forKey: cacheKey)
            return
        }
        struct Params: Encodable { let p_workspace: UUID; let p_user: UUID; let p_item: String; let p_equipped: Bool }
        snapshot = try await client.rpc("wolfy_equip", params: Params(p_workspace: workspace,p_user: user,p_item: item.id,p_equipped: enabled)).execute().value
    }
    private func flushEquipment() async {
        guard NetworkMonitor.shared.isOnline, let pending = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Bool] else { return }
        for (id, enabled) in pending {
            guard let item = snapshot?.catalog?.first(where: { $0.id == id }), snapshot?.owned.contains(id) == true else { continue }
            do {
                try await equip(item, enabled: enabled)
                var remaining = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Bool] ?? [:]
                remaining.removeValue(forKey: id); UserDefaults.standard.set(remaining, forKey: cacheKey)
            } catch { return }
        }
    }
    func interact(_ kind: String, answer: String? = nil) async throws {
        struct Params: Encodable { let p_workspace: UUID; let p_user: UUID; let p_kind: String; let p_answer: String? }
        snapshot = try await client.rpc("wolfy_interact", params: Params(p_workspace: workspace,p_user: user,p_kind: kind,p_answer: answer)).execute().value
    }
    func failure(_ message: String) -> NSError { NSError(domain: "Wolfy",code: 1,userInfo: [NSLocalizedDescriptionKey: message]) }
}
