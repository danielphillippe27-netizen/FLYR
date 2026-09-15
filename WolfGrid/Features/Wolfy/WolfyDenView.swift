import SwiftUI

struct WolfyHomeCompanion: View {
    let user: UUID
    let workspace: UUID
    let summary: WolfyHomeSummary
    let active: Bool
    let insight: String
    var coach: WolfyCoachStore? = nil
    let work: () -> Void
    @StateObject private var economy: WolfyEconomyStore
    @AppStorage("wolfy.gamification") private var gamification = WolfyFeatureDefaults.enabled
    @State private var den = false
    init(user: UUID, workspace: UUID, summary: WolfyHomeSummary, active: Bool, insight: String, coach: WolfyCoachStore? = nil, work: @escaping () -> Void) {
        self.user=user;self.workspace=workspace;self.summary=summary;self.active=active;self.insight=insight;self.work=work;self.coach=coach
        _economy=StateObject(wrappedValue:WolfyEconomyStore(user:user,workspace:workspace))
    }
    private var mood: WolfyMood {
        WolfyMood.resolve(hour:Calendar.current.component(.hour,from:Date()),workStart:economy.snapshot?.profile.work_start ?? 9,
                          workEnd:economy.snapshot?.profile.work_end ?? 18,dnd:economy.snapshot?.profile.dnd ?? false,active:active,
                          doors:summary.metrics?.doors,target:summary.goals?.daily_door_goal,
                          overdue:summary.followUps.map{$0.filter{($0.dueDate ?? .distantFuture)<Date()}.count},happiness:economy.snapshot?.profile.happiness ?? 60)
    }
    var body: some View {
        if gamification {
            VStack(spacing:6) {
                WolfyPortraitView(xp:economy.snapshot?.profile.xp,celebrationID:economy.celebration?.id,resting:mood.state == .resting,suspended:den,equipment:economy.effectiveEquipment,onTap:{ den=true }).frame(height:240)
                Button("Visit Wolfy's Den") { den=true }.font(.subheadline)
                if let wallet=economy.snapshot?.profile {
                    Text("\(WolfyProgression.rank(level:WolfyProgression.level(xp:wallet.xp))) · \(wallet.xp) XP · \(wallet.spendable_xp.map { $0.formatted() } ?? "—") XP available").font(.caption)
                }
            }
            .sheet(isPresented:$den) {
                WolfyDenView(economy:economy,mood:mood,insight:insight,work:work,streak:summary.stats?.day_streak,coach:coach,coachUser:user,coachWorkspace:workspace)
            }
            .task {
                await economy.refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for:.seconds(30)) } catch { return }
                    await economy.refresh()
                }
            }
        } else {
            Button("Wolfy settings") { den=true }
                .sheet(isPresented:$den) { WolfyDenView(economy:economy,mood:mood,insight:insight,work:work,streak:summary.stats?.day_streak,coach:coach,coachUser:user,coachWorkspace:workspace) }
        }
    }
}

struct WolfyDenView: View {
    @ObservedObject var economy: WolfyEconomyStore
    let mood: WolfyMood
    let insight: String
    let work: () -> Void
    var streak: Int? = nil
    var coach: WolfyCoachStore? = nil
    var coachUser: UUID? = nil
    var coachWorkspace: UUID? = nil
    @State private var reactionID: String?
    @State private var previewStage: Int?
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var busy=false
    @State private var train=false
    @State private var rest=false
    @State private var workStart=9
    @State private var workEnd=18
    @AppStorage("wolfy.gamification") private var gamification=WolfyFeatureDefaults.enabled
    @AppStorage("wolfy.haptics") private var haptics=true
    @AppStorage("wolfy.sound") private var sound=false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:18) {
                    WolfyPortraitView(xp:economy.snapshot?.profile.xp,previewStage:previewStage,celebrationID:reactionID ?? economy.celebration?.id,resting:rest,equipment:economy.effectiveEquipment).frame(height:320)
                    if let previewStage {
                        Text("Preview · Stage \(previewStage) of 5").font(.subheadline)
                        Button("Back to my Wolfy") { self.previewStage=nil }
                    } else if let xp=economy.snapshot?.profile.xp {
                        Text("Stage \(WolfyProgression.growthStage(xp:xp)) of 5").font(.subheadline)
                    } else {
                        Text("Growth progress unavailable").font(.subheadline).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Five growth stages") {
                        ForEach(1...5,id:\.self) { stage in
                            Button { previewStage=stage } label: {
                                HStack {
                                    Image("WolfyStage\(stage)").resizable().scaledToFit().frame(width:56,height:56).clipShape(RoundedRectangle(cornerRadius:8))
                                    VStack(alignment:.leading) {
                                        Text("Stage \(stage) · \(WolfyProgression.rank(level:WolfyProgression.growthLevels[stage-1]))")
                                        Text("Level \(WolfyProgression.growthLevels[stage-1]) · \(WolfyProgression.floorXP(level:WolfyProgression.growthLevels[stage-1])) XP").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName:"eye")
                                }
                            }.buttonStyle(.plain).accessibilityLabel("Preview growth stage \(stage)")
                        }
                    }
                    if let p=economy.snapshot?.profile {
                        let level=WolfyProgression.level(xp:p.xp)
                        Text("Level \(level) · \(WolfyProgression.rank(level:level))").font(.title2.bold())
                        Text("\(p.xp) lifetime XP · \(p.spendable_xp.map { $0.formatted() } ?? "—") XP available").font(.headline)
                        if level<100 {
                            ProgressView(value:Double(p.xp-WolfyProgression.floorXP(level:level)),total:Double(WolfyProgression.floorXP(level:level+1)-WolfyProgression.floorXP(level:level)))
                        }
                    }
                    if let streak { Text("\(streak)-day activity streak").font(.caption) }
                    Text(insight).font(.headline).frame(maxWidth:.infinity,alignment:.leading)
                    Button("Continue your work") { dismiss();work() }.buttonStyle(.borderedProminent)
                    HStack {
                        attribute("Energy",mood.energy);attribute("Happiness",economy.snapshot?.profile.happiness);attribute("Pipeline Health",mood.health)
                    }
                    Text("Pipeline Health is an estimate from overdue follow-ups, not physical health. Rest never costs XP or items.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Feed") { interact("feed") }
                        Button("Play") { interact("play") }
                        Button("Train") { train=true }
                    }.buttonStyle(.bordered).disabled(busy || economy.snapshot==nil)
                    if let coach, let user = coachUser, let workspace = coachWorkspace {
                        NavigationLink { WolfyCoachView(coach:coach,user:user,workspace:workspace) } label: {
                            Label("Ask Wolfy",systemImage:"bubble.left.and.bubble.right.fill").font(.headline)
                        }.buttonStyle(.borderedProminent)
                    }
                    NavigationLink("Store & Locker") { WolfyPortraitStoreView(economy:economy) }
                    NavigationLink("Stats") { YouStatsView() }
                    NavigationLink("Achievements") {
                        List(economy.snapshot?.achievements ?? [],id:\.self) { Text($0.replacingOccurrences(of:"_",with:" ").capitalized) }.navigationTitle("Achievements")
                    }
                    if let error=error ?? economy.error { Text(error).foregroundStyle(.secondary);Button("Retry") { Task { await economy.refresh() } } }
                    GroupBox("Character controls") {
                        Toggle("Do Not Disturb",isOn:$rest)
                        Stepper("Work starts: \(workStart):00",value:$workStart,in:0...23)
                        Stepper("Work ends: \(workEnd):00",value:$workEnd,in:0...23)
                        Button("Save working hours") {
                            Task { do { try await economy.settings(start:workStart,end:workEnd,dnd:rest) } catch { self.error=error.localizedDescription } }
                        }
                        Toggle("Gamification",isOn:$gamification)
                        Toggle("Haptics",isOn:$haptics)
                        Toggle("Sounds",isOn:$sound)
                        Text("No character notifications or voice synchronization are enabled.").font(.caption)
                    }
                }.padding()
            }.navigationTitle("Wolfy's Den")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
                .onChange(of:economy.celebration?.id) { _, value in reactionID=value }
                .sheet(isPresented:$train) { WolfyTrainingView(economy:economy) }
                .task {
                    if economy.snapshot == nil { await economy.refresh() }
                    rest=economy.snapshot?.profile.dnd ?? false
                    workStart=economy.snapshot?.profile.work_start ?? 9
                    workEnd=economy.snapshot?.profile.work_end ?? 18

                }
        }
    }
    private func attribute(_ title:String,_ value:Int?) -> some View {
        VStack { Text(value.map(String.init) ?? "—").font(.title2.bold());Text(title).font(.caption) }.frame(maxWidth:.infinity)
    }
    private func interact(_ kind:String) {
        busy=true
        Task {
            defer { busy=false }
            do { try await economy.interact(kind);reactionID=UUID().uuidString;WolfyFeedback.perform();error=nil }
            catch { self.error=error.localizedDescription }
        }
    }
}

struct WolfyLockerView: View {
    @ObservedObject var economy: WolfyEconomyStore
    @StateObject private var character=WolfyCharacterController()
    @State private var section="Owned"
    @State private var selection: WolfyCatalogItem?
    @State private var previewReady=false
    @State private var confirming=false
    @State private var busy=false
    @State private var message: String?
    @State private var request=UUID()
    init(economy:WolfyEconomyStore,initialSection:String="Owned") {
        self.economy=economy;_section=State(initialValue:initialSection)
    }
    let sections=["Equipped","Owned","Store","Locked","Achievements"]
    private func isLocked(_ item:WolfyCatalogItem) -> Bool {
        WolfyProgression.level(xp:economy.snapshot?.profile.xp ?? 0)<item.required_level ||
        item.required_achievement.map { economy.snapshot?.achievements.contains($0) != true } == true
    }
    private var items:[WolfyCatalogItem] {
        (economy.snapshot?.catalog ?? []).filter { item in
            let owned=economy.snapshot?.owned.contains(item.id)==true
            let locked=isLocked(item)
            switch section {
            case "Equipped":return economy.snapshot?.equipped.values.contains(item.id)==true
            case "Owned":return owned
            case "Locked":return locked
            case "Achievements":return item.required_achievement != nil
            default:return !owned && !locked
            }
        }.sorted{$0.price<$1.price}
    }
    var body: some View {
        ScrollView {
            VStack(spacing:14) {
                WolfyCharacterView(controller:character).frame(height:260)
                Text("\(economy.snapshot?.profile.coins ?? 0) Grid Coins · XP is never spent").font(.subheadline)
                Picker("Section",selection:$section) { ForEach(sections,id:\.self) { Text($0) } }.pickerStyle(.menu)
                if let item=selection {
                    Text(item.name).font(.headline)
                    Text("\(item.rarity.capitalized) · Level \(item.required_level) · \(WolfyProgression.rank(level:item.required_level))").font(.caption)
                    if let achievement=item.required_achievement { Text("Requires \(achievement)") }
                    if economy.snapshot?.owned.contains(item.id)==true {
                        Button("Equip") { equip(item,true) }.disabled(!previewReady || busy)
                        Button("Unequip") { equip(item,false) }.disabled(busy)
                    } else {
                        Button("Buy for \(item.price) Coins") { confirming=true }.buttonStyle(.borderedProminent)
                            .disabled(!previewReady || busy || isLocked(item))
                    }
                    Text("Preview only until equipped. Drag Wolfy to rotate.").font(.caption).foregroundStyle(.secondary)
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if items.isEmpty { Text("No items in this section.").foregroundStyle(.secondary) }
                ForEach(items) { item in
                    Button { preview(item) } label: {
                        HStack {
                            if let url=WolfyAssetLoader.url(item.id+".png"),let image=UIImage(contentsOfFile:url.path) {
                                Image(uiImage:image).resizable().scaledToFit().frame(width:52,height:52)
                            }
                            VStack(alignment:.leading) { Text(item.name);Text(item.category.capitalized).font(.caption) };Spacer();Text(item.price==0 ? "Free" : "\(item.price) Coins") }.padding()
                    }.buttonStyle(.bordered).disabled(busy)
                }
            }.padding()
        }.navigationTitle("Wolfy Locker")
            .task { await character.load() }
            .alert("Purchase accessory?",isPresented:$confirming) {
                Button("Buy & Equip") {
                    guard let item=selection else { return };busy=true
                    Task {
                        defer { busy=false }
                        do {
                            try await economy.purchase(item,request:request)
                            try await character.preview(item)
                            try await economy.equip(item,enabled:true)
                            character.trigger(.customizing);WolfyFeedback.perform();message="Purchased and equipped."
                        } catch { message="Could not finish purchase/equip: \(error.localizedDescription)" }
                    }
                }
                Button("Cancel",role:.cancel) {}
            } message: { Text("Spend \(selection?.price ?? 0) Grid Coins. Your XP stays unchanged.") }
    }
    private func preview(_ item:WolfyCatalogItem) {
        selection=item;request=UUID();previewReady=false;message=nil
        Task {
            do { try await character.preview(item);if selection?.id==item.id { previewReady=true } }
            catch { message="Asset unavailable. Purchase and equip are disabled." }
        }
    }
    private func equip(_ item:WolfyCatalogItem,_ enabled:Bool) {
        busy=true
        Task {
            defer { busy=false }
            do {
                try await character.preview(item,enabled:enabled)
                try await economy.equip(item,enabled:enabled)
                message=NetworkMonitor.shared.isOnline ? "Outfit saved." : "Outfit queued for synchronization."
                character.trigger(.customizing)
            } catch { message=error.localizedDescription }
        }
    }
}

private struct WolfyTrainingView: View {
    @ObservedObject var economy:WolfyEconomyStore
    @Environment(\.dismiss) private var dismiss
    @State private var feedback:String?
    @State private var busy=false
    var body: some View {
        NavigationStack {
            List {
                Text("The homeowner says: ‘I'm not interested.’ What do you do next?").font(.headline)
                Button("Acknowledge it, then ask permission for one question") {
                    busy=true
                    Task {
                        defer { busy=false }
                        do { try await economy.interact("train",answer:"ask_permission");feedback="Good. Respect their time: ‘Understood. May I ask one quick question before I go?’ Training rewards are limited to once per UTC day." }
                        catch { feedback=error.localizedDescription }
                    }
                }.disabled(busy)
                Button("Continue the pitch without pausing") { feedback="Pause and acknowledge the objection. A short permission-based question gives the homeowner control." }
                Button("Insist that every homeowner needs an inspection") { feedback="Avoid pressure or unsupported claims. Ask about their situation and respect a clear no." }
                if let feedback { Text(feedback) }
            }.navigationTitle("Door-opener practice").toolbar { Button("Done") { dismiss() } }
        }
    }
}
