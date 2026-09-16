import SwiftUI

struct WolfyPortraitStoreView: View {
    @ObservedObject var economy: WolfyEconomyStore
    @State private var selection: WolfyPortraitAccessory?
    @State private var section = "All"
    @State private var category = "Everything"
    @State private var previewStage: Int?
    @State private var request = UUID()
    @State private var busy = false
    @State private var message: String?
    private var stage: Int { previewStage ?? WolfyProgression.growthStage(xp:economy.snapshot?.profile.xp ?? 0) }
    private var balance: Int? { economy.snapshot?.profile.spendable_xp }
    private var equipment: [String:String] {
        var result=economy.effectiveEquipment
        if let selection { result[selection.slot]=selection.id }
        return result
    }
    private func item(_ definition:WolfyPortraitAccessory) -> WolfyCatalogItem? {
        economy.snapshot?.catalog?.first { $0.id==definition.id && $0.render_kind=="portrait" && $0.price_currency=="xp" }
    }
    private func owned(_ id:String) -> Bool { economy.snapshot?.owned.contains(id)==true }
    private func equipped(_ id:String) -> Bool { economy.effectiveEquipment.values.contains(id) }
    private var items: [WolfyPortraitAccessory] {
        WolfyPortraitAccessory.all.filter { definition in
            let matchesSection=section=="All" || (section=="Owned" && owned(definition.id)) || (section=="Equipped" && equipped(definition.id))
            let prefix=switch category { case "Chains":"chain";case "Glasses":"glasses";case "Collars":"collar";case "Effects":"aura";default:"" }
            return matchesSection && definition.key.hasPrefix(prefix)
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing:18) {
                WolfyPortraitView(xp:economy.snapshot?.profile.xp,previewStage:stage,equipment:equipment).frame(height:300)
                Text(selection.map { "Preview · \($0.name)" } ?? "Your Wolfy").font(.title3.bold())
                if selection != nil { Button("Clear preview") { selection=nil;message=nil }.disabled(busy) }
                Text(balance.map { "\($0.formatted()) XP available" } ?? "XP balance unavailable").font(.headline)
                Text("Purchases use spendable XP. Lifetime XP keeps your stage and rank.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Picker("Preview growth stage",selection:Binding(get:{stage},set:{previewStage=$0})) {
                    ForEach(1...5,id:\.self) { Text("Stage \($0)").tag($0) }
                }.pickerStyle(.menu).disabled(busy)
                if previewStage != nil { Button("Use my growth stage") { previewStage=nil }.font(.caption) }
                if let selection { purchaseControls(selection) }
                if let message { Text(message).font(.subheadline).accessibilityAddTraits(.updatesFrequently) }
                if balance==nil || economy.error != nil {
                    Text(economy.error ?? "The XP store is unavailable. You can still preview the collection.").font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { Task { await economy.refresh() } }.disabled(busy)
                }
                Picker("Collection",selection:$section) { ForEach(["All","Owned","Equipped"],id:\.self) { Text($0) } }.pickerStyle(.segmented)
                Picker("Accessory type",selection:$category) { ForEach(["Everything","Chains","Glasses","Collars","Effects"],id:\.self) { Text($0) } }.pickerStyle(.menu)
                if items.isEmpty { Text("No accessories in this collection yet.").foregroundStyle(.secondary) }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:12) {
                    ForEach(items) { definition in
                        Button {
                            selection=definition;request=UUID();message=nil
                        } label: {
                            VStack(alignment:.leading,spacing:8) {
                                WolfyPortraitComposition(stage:stage,equipment:[definition.slot:definition.id]).clipShape(RoundedRectangle(cornerRadius:14))
                                Text(definition.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                Text(equipped(definition.id) ? "Equipped" : owned(definition.id) ? "Owned" : item(definition).map { "\($0.price.formatted()) XP" } ?? "Preview").font(.caption).foregroundStyle(.secondary)
                            }.padding(10).background(.quaternary,in:RoundedRectangle(cornerRadius:18))
                        }.buttonStyle(.plain).disabled(busy)
                        .accessibilityLabel("Preview \(definition.name)")
                    }
                }
            }.padding()
        }.navigationTitle("Store & Locker")
        .task { if economy.snapshot==nil || balance==nil { await economy.refresh() } }
        .refreshable { await economy.refresh() }
    }
    @ViewBuilder private func purchaseControls(_ definition:WolfyPortraitAccessory) -> some View {
        if let item=item(definition), balance != nil {
            let locked=WolfyProgression.level(xp:economy.snapshot?.profile.xp ?? 0)<item.required_level || item.required_achievement.map { economy.snapshot?.achievements.contains($0) != true } == true
            if owned(definition.id) {
                Button(equipped(definition.id) ? "Unequip" : "Equip") { equip(item,!equipped(definition.id)) }.buttonStyle(.borderedProminent).disabled(busy)
            } else {
                Button(busy ? "Purchasing…" : "Buy & Equip · \(item.price.formatted()) XP") { purchase(item) }
                    .buttonStyle(.borderedProminent).disabled(busy || locked || (balance ?? 0)<item.price)
                if locked { Text("Requires level \(item.required_level)\(item.required_achievement == nil ? "" : " and its achievement")").font(.caption) }
                else if (balance ?? 0)<item.price { Text("Earn \((item.price-(balance ?? 0)).formatted()) more XP to buy this.").font(.caption) }
            }
        }
    }
    private func purchase(_ item:WolfyCatalogItem) {
        busy=true;message=nil
        Task {
            defer { busy=false }
            do {
                try await economy.purchase(item,request:request)
                selection=nil
                message="Purchased and equipped. Your lifetime XP is unchanged."
                WolfyFeedback.perform()
            } catch { message="Purchase could not be confirmed. Retry with the same item: \(error.localizedDescription)" }
        }
    }
    private func equip(_ item:WolfyCatalogItem,_ enabled:Bool) {
        busy=true;message=nil
        Task {
            defer { busy=false }
            do {
                try await economy.equip(item,enabled:enabled)
                selection=nil
                message=NetworkMonitor.shared.isOnline ? "Outfit saved." : "Outfit saved on this device; it will sync when connected."
            } catch { message="Could not save outfit: \(error.localizedDescription)" }
        }
    }
}
