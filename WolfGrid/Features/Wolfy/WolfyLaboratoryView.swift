#if DEBUG
import SwiftUI

@MainActor struct WolfyLaboratoryEntryView: View {
    @StateObject private var economy:WolfyEconomyStore
    @StateObject private var coach=WolfyCoachStore()
    init() {
        let store=WolfyEconomyStore(user:UUID(uuidString:"00000000-0000-0000-0000-000000000001")!,workspace:UUID(uuidString:"00000000-0000-0000-0000-000000000002")!)
        if let url=WolfyAssetLoader.url("wolfy_manifest.json"),let data=try? Data(contentsOf:url),let manifest=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let items=manifest["items"] as? [[String:Any]] {
            let legacyCatalog=items.map { item -> [String:Any] in var copy=item;copy["required_level"]=item["requiredLevel"];return copy }
            let catalog=legacyCatalog + WolfyPortraitAccessory.all.map { definition -> [String:Any] in
                ["id":definition.id,"name":definition.name,"category":definition.slot,"socket":"portrait_"+definition.slot,"rarity":"common","price":definition.price,"required_level":1,"asset":definition.key,"render_kind":"portrait","price_currency":"xp"]
            }
            let fixture:[String:Any]=["profile":["xp":10000,"coins":2500,"spendable_xp":2500,"happiness":75,"work_start":9,"work_end":18,"dnd":false],"owned":["default_hoodie","default_pants","default_shoes","basic_collar","default_den","cap"],"equipped":["head":"cap"],"achievements":["first_qualified_lead"],"catalog":catalog]
            if let data=try? JSONSerialization.data(withJSONObject:fixture) { store.snapshot=try? JSONDecoder().decode(WolfySnapshot.self,from:data) }
        }
        _economy=StateObject(wrappedValue:store)
    }
    var body:some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--wolfy-coach") {
                NavigationStack { WolfyCoachView(coach:coach,user:UUID(),workspace:UUID()) }
            } else if ProcessInfo.processInfo.arguments.contains("--wolfy-accessory-review") {
                WolfyAccessoryReviewView()
            } else if ProcessInfo.processInfo.arguments.contains("--wolfy-den") {
                WolfyDenView(economy:economy,mood:WolfyMood(state:.focused,energy:75,happiness:75,health:90),insight:"Preview: two follow-ups are due. Review them before your next campaign.",work:{})
            } else if ProcessInfo.processInfo.arguments.contains("--wolfy-store") {
                NavigationStack { WolfyPortraitStoreView(economy:economy) }
            } else { WolfyLaboratoryView() }
        }.safeAreaInset(edge:.bottom) { Text("DEBUG VISUAL FIXTURE · NOT LIVE ACCOUNT DATA").font(.caption2).dynamicTypeSize(.xSmall ... .large).padding(4).background(.orange.opacity(0.2)) }
    }
}

/// Available only in a Debug binary launched explicitly with --wolfy-lab.
struct WolfyLaboratoryView: View {
    @StateObject private var character=WolfyCharacterController()
    @State private var clip="idle_neutral"
    @State private var selectedItem=""
    @State private var level=1
    @State private var reduced=false
    @State private var missing=false
    @State private var error:String?
    private var catalog:[WolfyCatalogItem] {
        guard let url=WolfyAssetLoader.url("wolfy_manifest.json"), let data=try? Data(contentsOf:url),
              let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let items=json["items"] as? [[String:Any]] else { return [] }
        return items.compactMap { item in
            var mapped=item;mapped["required_level"]=item["requiredLevel"]
            return (try? JSONSerialization.data(withJSONObject:mapped)).flatMap{try? JSONDecoder().decode(WolfyCatalogItem.self,from:$0)}
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:12) {
                    Text("DEVELOPER LAB · No business rewards").font(.caption.bold()).foregroundStyle(.orange)
                    WolfyCharacterView(controller:character,forceReducedMotion:reduced).frame(height:350)
                    Text(character.description)
                    Text("Level \(level) · \(WolfyProgression.rank(level:level))")
                    Stepper("Preview level",value:$level,in:1...100).onChange(of:level) { _,value in character.setLevel(value) }
                    Picker("Animation",selection:$clip) { ForEach(WolfyAssetLoader.shared.manifest?.animations.map(\.name) ?? [],id:\.self) { Text($0) } }
                    Button("Play clip") { character.laboratoryClip(clip) }
                    HStack {
                        Button("Lead") { character.trigger(.lead) }
                        Button("Appointment") { character.trigger(.appointment) }
                        Button("Sale") { character.trigger(.sale) }
                    }
                    Button("Missed goal") { character.trigger(.encouraging) }
                    Picker("Accessory",selection:$selectedItem) { Text("None").tag("");ForEach(catalog) { Text($0.name).tag($0.id) } }
                    Button("Preview accessory") {
                        if let item=catalog.first(where:{$0.id==selectedItem}) { Task { do {try await character.preview(item)} catch {self.error=error.localizedDescription} } }
                    }
                    Toggle("Reduce Motion",isOn:$reduced)
                    Toggle("Missing asset fallback",isOn:$missing).onChange(of:missing) { _,value in character.failed=value }
                    Button("Reset asset cache") { WolfyAssetLoader.shared.reset() }
                    if let error { Text(error) }
                }.padding()
            }.navigationTitle("Wolfy Laboratory")
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--wolfy-demo") {
                        await character.load()
                        try? await Task.sleep(for:.seconds(4))
                        character.trigger(.sale)
                        try? await Task.sleep(for:.seconds(4))
                        if let item=catalog.first(where:{$0.id=="cap"}) { try? await character.preview(item);character.trigger(.customizing) }
                    }
                }
        }
    }
}
struct WolfyAccessoryReviewView: View {
    @State private var stage=1
    private var equipment:[String:String] {
        let args=ProcessInfo.processInfo.arguments
        if let key=args.first(where:{$0.hasPrefix("--accessory=")})?.replacingOccurrences(of:"--accessory=",with:""),let item=WolfyPortraitAccessory.find(key) { return [item.slot:item.id] }
        return ["neck":"portrait_chain_gold","eyewear":"portrait_glasses_aviator","aura":"portrait_aura_ember"]
    }
    var body:some View {
        VStack(spacing:20) {
            Text("Accessory fit · Stage \(stage)").font(.title2)
            WolfyPortraitView(xp:0,previewStage:stage,equipment:equipment).frame(height:380)
            Stepper("Growth stage",value:$stage,in:1...5)
        }.padding().task {
            if ProcessInfo.processInfo.arguments.contains("--export-accessories") {
                let renderer=ImageRenderer(content:WolfyAccessoryContactSheet().frame(width:1000).environment(\.colorScheme,.light))
                renderer.scale=2
                if let data=renderer.uiImage?.pngData() {
                    let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("wolfy-accessory-collection.png")
                    try? data.write(to:url)
                }
            }
            if let value=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--stage=")})?.replacingOccurrences(of:"--stage=",with:""),let number=Int(value) { stage=min(5,max(1,number)) }
        }
    }
}
private struct WolfyAccessoryContactSheet: View {
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("WOLFY · FIRST COLLECTION").font(.system(size:34,weight:.bold))
            Text("16 portrait accessories · Spendable XP purchases · Lifetime XP stays yours").font(.system(size:17)).foregroundStyle(.secondary)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:16),count:4),spacing:20) {
                ForEach(WolfyPortraitAccessory.all) { item in
                    VStack(alignment:.leading,spacing:7) {
                        WolfyPortraitComposition(stage:2,equipment:[item.slot:item.id]).frame(height:210).clipShape(RoundedRectangle(cornerRadius:16))
                        Text(item.name).font(.system(size:17,weight:.semibold))
                        Text("\(item.price) XP").font(.system(size:15)).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Design preview · Prices match the migration catalog · Live store requires backend migration").font(.system(size:13)).foregroundStyle(.secondary)
        }.padding(30).background(Color.white)
    }
}
#endif
