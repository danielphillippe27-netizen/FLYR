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
    private var expression: WolfyPocketExpression {
        if let overdue = summary.followUps?.filter({ ($0.dueDate ?? .distantFuture) < Date() }).count, overdue > 0 { return .alert }
        if let goal = summary.goals?.weekly_door_goal, let weekly = summary.metrics?.weekly_doors, weekly >= goal { return .celebrating }
        guard let doors = summary.metrics?.doors, doors > 0 else { return .resting }
        if (summary.stats?.day_streak ?? 0) >= 7 { return .proud }
        if let goal = summary.goals?.weekly_door_goal, let doors = summary.metrics?.weekly_doors {
            let delta = WolfyHomePolicy.weeklyPaceDelta(target: goal, completed: doors, now: Date())
            if delta < 0 { return .focused }
            if delta > 0 { return .excited }
        }
        return .normal
    }
    var body: some View {
        if gamification {
            Button { den = true } label: {
                WolfyPocketPet(resting: mood.state == .resting, expression: expression)
                    .frame(maxWidth: 76).aspectRatio(76.0 / 84.0, contentMode: .fit)
            }.buttonStyle(.plain).accessibilityLabel("Visit Wolfy's Den")
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
                    WolfyIllustratedDen(stage: previewStage ?? economy.snapshot.map { WolfyProgression.growthStage(xp: $0.profile.xp) } ?? 1, resting: rest || mood.state == .resting).frame(height: 300)
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
                                    WolfyPocketPet().frame(width: 56, height: 56)
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


/// A small vector companion: no asset download or 3D scene is needed on Home.
enum WolfyPocketExpression: String {
    case normal, excited, focused, celebrating, resting, alert, proud
}

struct WolfyPocketPet: View {
    var resting = false
    var expression: WolfyPocketExpression = .normal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: reduceMotion || scenePhase != .active)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let lift = reduceMotion ? 0 : sin(time * 1.8) * 1.3
            Canvas { context, size in
                let sx = size.width / 100, sy = size.height / 110
                context.scaleBy(x: sx, y: sy)
                func oval(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
                }
                func polygon(_ points: [CGPoint], _ color: Color) {
                    var path = Path(); path.addLines(points); path.closeSubpath()
                    context.fill(path, with: .color(color))
                }
                let fur = Color(red: 0.36, green: 0.42, blue: 0.51)
                let pale = Color(red: 0.88, green: 0.91, blue: 0.96)
                oval(16, 99, 70, 8, .black.opacity(0.12))
                context.translateBy(x: 0, y: lift)
                oval(62, 70, 30, 26, fur)
                oval(24, 52, 51, 47, fur)
                oval(35, 63, 29, 31, pale)
                oval(21, 91, 24, 12, fur)
                oval(57, 91, 24, 12, fur)
                polygon([CGPoint(x: 18,y: 43),CGPoint(x: 17,y: 5),CGPoint(x: 42,y: 27)], fur)
                polygon([CGPoint(x: 58,y: 27),CGPoint(x: 83,y: 5),CGPoint(x: 82,y: 43)], fur)
                polygon([CGPoint(x: 23,y: 29),CGPoint(x: 22,y: 14),CGPoint(x: 34,y: 28)], .pink.opacity(0.65))
                polygon([CGPoint(x: 66,y: 28),CGPoint(x: 78,y: 14),CGPoint(x: 77,y: 29)], .pink.opacity(0.65))
                oval(15, 22, 70, 52, fur)
                polygon([CGPoint(x: 16,y: 44),CGPoint(x: 6,y: 51),CGPoint(x: 25,y: 57)], fur)
                polygon([CGPoint(x: 84,y: 44),CGPoint(x: 94,y: 51),CGPoint(x: 75,y: 57)], fur)
                oval(25, 43, 50, 28, pale)
                let blink = resting || expression == .resting || (!reduceMotion && time.truncatingRemainder(dividingBy: 5) < 0.18)
                oval(30, 39, 8, blink ? 2 : 10, .init(white: 0.08))
                oval(62, 39, 8, blink ? 2 : 10, .init(white: 0.08))
                if !blink { oval(32,40,2,3,.white); oval(64,40,2,3,.white) }
                polygon([CGPoint(x: 44,y: 51),CGPoint(x: 56,y: 51),CGPoint(x: 50,y: 58)], .init(white: 0.08))
                var smile = Path(); smile.move(to: CGPoint(x: 43,y: 61)); smile.addQuadCurve(to: CGPoint(x: 57,y: 61),control: CGPoint(x: 50,y: expression == .focused ? 61 : 67))
                context.stroke(smile, with: .color(.init(white: 0.2)), lineWidth: 1.7)
                polygon([CGPoint(x: 27,y: 69),CGPoint(x: 73,y: 69),CGPoint(x: 51,y: 83)], .red)
                if expression == .focused || expression == .alert {
                    var brow = Path()
                    brow.move(to: CGPoint(x: 29, y: 34)); brow.addLine(to: CGPoint(x: 40, y: 37))
                    brow.move(to: CGPoint(x: 60, y: 37)); brow.addLine(to: CGPoint(x: 71, y: 34))
                    context.stroke(brow, with: .color(.init(white: 0.12)), lineWidth: 2)
                }
                if expression == .celebrating || expression == .excited || expression == .proud {
                    context.draw(Text(expression == .proud ? "✦" : "✧").font(.system(size: 18)).foregroundColor(.yellow), at: CGPoint(x: 91, y: 18))
                    oval(25, 51, 9, 4, .pink.opacity(0.4))
                    oval(66, 51, 9, 4, .pink.opacity(0.4))
                }
                if resting || expression == .resting {
                    context.draw(Text("z").font(.system(size: 15, weight: .semibold)).foregroundColor(.secondary), at: CGPoint(x: 89,y: 19))
                }
            }
        }.accessibilityLabel(resting ? "Wolfy is resting" : "Wolfy is \(expression.rawValue)")
    }
}

private struct WolfyIllustratedDen: View {
    let stage: Int
    let resting: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.09, green: 0.12, blue: 0.19), Color(red: 0.18, green: 0.16, blue: 0.20)], startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    let window = CGRect(x: size.width * 0.30, y: 24, width: size.width * 0.61, height: 145)
                    context.fill(Path(roundedRect: window, cornerRadius: 16), with: .color(Color(red: 0.12, green: 0.21, blue: 0.32)))
                    context.fill(Path(ellipseIn: CGRect(x: window.maxX - 43, y: 40, width: 23, height: 23)), with: .color(.white.opacity(0.8)))
                    for index in 0..<3 {
                        let x = window.minX + Double(index) * window.width / 3
                        var mountain = Path()
                        mountain.move(to: CGPoint(x: x, y: window.maxY))
                        mountain.addLine(to: CGPoint(x: x + window.width / 6, y: 78 + Double(index % 2) * 18))
                        mountain.addLine(to: CGPoint(x: min(window.maxX, x + window.width / 3), y: window.maxY))
                        mountain.closeSubpath()
                        context.fill(mountain, with: .color(.white.opacity(0.09 + Double(index) * 0.025)))
                    }
                    context.fill(Path(CGRect(x: 0, y: 221, width: size.width, height: size.height - 221)), with: .color(.black.opacity(0.22)))
                    context.fill(Path(ellipseIn: CGRect(x: size.width * 0.28, y: 232, width: size.width * 0.52, height: 39)), with: .color(.red.opacity(0.20)))
                }
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(0..<max(1, min(stage, 5)), id: \.self) { _ in
                            Image(systemName: stage > 3 ? "trophy.fill" : "star.fill").foregroundStyle(.yellow.opacity(0.85)).font(.caption)
                        }
                    }
                    Rectangle().fill(.white.opacity(0.15)).frame(height: 3)
                }.frame(width: geometry.size.width * 0.23).position(x: geometry.size.width * 0.16, y: 109)
                Image(systemName: "flame.fill").font(.system(size: 42)).foregroundStyle(.orange.gradient)
                    .padding(15).background(.black.opacity(0.3), in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
                    .position(x: geometry.size.width * 0.15, y: 210)
                WolfyPocketPet(resting: resting).frame(width: 136, height: 150).position(x: geometry.size.width * 0.59, y: 205)
                VStack {
                    Spacer()
                    HStack {
                        Text(["Rookie", "Street Wolf", "Veteran", "Alpha", "Grid Legend"][max(0, min(stage - 1, 4))]).font(.caption.bold()).tracking(1.5)
                        Spacer()
                        Image(systemName: "moon.stars").font(.caption)
                    }.foregroundStyle(.white.opacity(0.65)).padding(16)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 26))
        }.accessibilityElement(children: .ignore).accessibilityLabel("Wolfy's mountain cabin, growth stage \(stage)")
    }
}
