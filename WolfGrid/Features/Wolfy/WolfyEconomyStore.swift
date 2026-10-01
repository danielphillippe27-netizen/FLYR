import Foundation
import Combine
import Supabase

extension Notification.Name { static let wolfyWardrobeDidChange = Notification.Name("wolfyWardrobeDidChange") }

@MainActor final class WolfyEconomyStore: ObservableObject {
    @Published var celebration: WolfyReward?
    @Published var snapshot: WolfySnapshot? {
        didSet {
            if let snapshot, let data=try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data,forKey:"wolfy.snapshot.\(workspace).\(user)")
            }
            NotificationCenter.default.post(name:.wolfyWardrobeDidChange,object:nil)
        }
    }
    @Published var error: String?
    @Published var busy = false
    let user: UUID
    let workspace: UUID
    private let client = SupabaseManager.shared.client
    private var cacheKey: String { "wolfy.equipment.\(workspace).\(user)" }
    private static let bundledWardrobe: [WolfyCatalogItem] = {
        guard let url=WolfyAssetLoader.url("wolfy_manifest.json"),
              let data=try? Data(contentsOf:url),
              let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let entries=json["items"] as? [[String:Any]] else { return [] }
        return entries.compactMap { entry -> WolfyCatalogItem? in
            guard (entry["asset"] as? String)?.hasPrefix("embedded:") == true else { return nil }
            var value=entry
            value["required_level"]=entry["requiredLevel"]
            value["render_kind"]="model3d"
            value["price_currency"]="coins"
            return (try? JSONSerialization.data(withJSONObject:value)).flatMap { try? JSONDecoder().decode(WolfyCatalogItem.self,from:$0) }
        }
    }()
    init(user: UUID, workspace: UUID) {
        self.user = user; self.workspace = workspace
        if let data=UserDefaults.standard.data(forKey:"wolfy.snapshot.\(workspace).\(user)") {
            // Restoring the cache is not a wardrobe change. Assigning through
            // snapshot here invokes didSet and posts a notification, which can
            // recursively create another store from the map marker observer.
            _snapshot = Published(initialValue: try? JSONDecoder().decode(WolfySnapshot.self,from:data))
        }
    }
    var catalog: [WolfyCatalogItem] {
        let remote=snapshot?.catalog ?? []
        let ids=Set(remote.map(\.id))
        return remote + Self.bundledWardrobe.filter { !ids.contains($0.id) }
    }
    var effectiveEquipment: [String:String] {
        var result=snapshot?.equipped ?? [:]
        for (id,enabled) in UserDefaults.standard.dictionary(forKey:cacheKey) as? [String:Bool] ?? [:] {
            guard let item=catalog.first(where:{$0.id==id}) else { continue }
            if enabled { result[item.category]=id } else { result.removeValue(forKey:item.category) }
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
        guard item.render_kind == "model3d" else { throw failure("This accessory cannot be equipped here.") }
        var pending = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Bool] ?? [:]
        if enabled {
            pending=pending.filter { id,_ in catalog.first(where:{$0.id==id})?.category != item.category }
        }
        pending[item.id] = enabled
        UserDefaults.standard.set(pending, forKey: cacheKey)
        NotificationCenter.default.post(name:.wolfyWardrobeDidChange,object:nil)
        guard NetworkMonitor.shared.isOnline else { return }
        struct Params: Encodable { let p_workspace: UUID; let p_user: UUID; let p_item: String; let p_equipped: Bool }
        do {
            snapshot = try await client.rpc("wolfy_equip", params: Params(p_workspace: workspace,p_user: user,p_item: item.id,p_equipped: enabled)).execute().value
            pending = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Bool] ?? [:]
            pending.removeValue(forKey:item.id)
            UserDefaults.standard.set(pending,forKey:cacheKey)
        } catch {
            // Keep the optimistic local choice visible and retry it during refresh.
            throw error
        }
    }
    private func flushEquipment() async {
        guard NetworkMonitor.shared.isOnline, let pending = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Bool] else { return }
        for (id, enabled) in pending {
            guard let item = catalog.first(where: { $0.id == id }) else { continue }
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
