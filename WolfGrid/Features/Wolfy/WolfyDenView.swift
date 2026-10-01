import SwiftUI

struct WolfyHomeCompanion: View {
    let user: UUID
    let workspace: UUID
    let summary: WolfyHomeSummary
    let active: Bool
    @State private var showingDen = false
    @StateObject private var economy: WolfyEconomyStore
    @StateObject private var character = WolfyCharacterController(compactFraming: true)
    @State private var reactingToHome = false
    init(user: UUID, workspace: UUID, summary: WolfyHomeSummary, active: Bool) {
        self.user=user;self.workspace=workspace;self.summary=summary;self.active=active
        _economy=StateObject(wrappedValue:WolfyEconomyStore(user:user,workspace:workspace))
    }
    private var mood: WolfyMood {
        WolfyMood.resolve(hour:Calendar.current.component(.hour,from:Date()),workStart:economy.snapshot?.profile.work_start ?? 9,
                          workEnd:economy.snapshot?.profile.work_end ?? 18,dnd:economy.snapshot?.profile.dnd ?? false,active:active,
                          doors:summary.metrics?.doors,target:summary.goals?.dailyTarget(),
                          overdue:summary.overdueFollowUps,happiness:economy.snapshot?.profile.happiness ?? 60)
    }
    var body: some View {
        VStack(spacing:8) {
            Button("Customize Wolf") { showingDen = true }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .frame(maxWidth:.infinity,alignment:.trailing)
            WolfyCharacterView(controller:character,mood:mood.state)
                .frame(width:220,height:220)
                .scaleEffect(reactingToHome ? 1.07 : 1)
                .rotationEffect(.degrees(reactingToHome ? -3 : 0))
                .animation(.spring(response:0.28,dampingFraction:0.42),value:reactingToHome)
                .contentShape(Rectangle())
                .onTapGesture { showingDen = true }
                .accessibilityLabel("3-D Wolfy. Tap to customize.")
            if let doors=summary.stats?.doors_knocked {
                let stage=WolfyProgression.growthStage(doors:doors)
                Text("\(WolfyProgression.growthStages[stage-1]) · \(doors.formatted()) doors")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth:.infinity,alignment:.center)
        .sheet(isPresented:$showingDen) {
            WolfyDenView(economy:economy,lifetimeDoors:summary.stats?.doors_knocked)
        }
        .onChange(of:showingDen) { _, isPresented in
            guard !isPresented else { return }
            character.configureAppearance(user:user,workspace:workspace)
            Task { await character.restore(economy.snapshot,equipment:economy.effectiveEquipment,catalog:economy.catalog) }
        }
        .task {
            await economy.refresh()
            character.configureAppearance(user:user,workspace:workspace)
            character.setGrowthStage(WolfyProgression.growthStage(doors:summary.stats?.doors_knocked ?? 0))
            await character.load()
            await character.restore(economy.snapshot,equipment:economy.effectiveEquipment,catalog:economy.catalog)
            while !Task.isCancelled {
                do { try await Task.sleep(for:.seconds(30)) } catch { return }
                await economy.refresh()
                await character.restore(economy.snapshot,equipment:economy.effectiveEquipment,catalog:economy.catalog)
            }
        }
        .onChange(of:summary.stats?.doors_knocked) { _, doors in
            character.setGrowthStage(WolfyProgression.growthStage(doors:doors ?? 0))
        }
        .onReceive(NotificationCenter.default.publisher(for:.wolfyHomeStatusDidChange)) { notification in
            guard let rawStatus = notification.userInfo?["status"] as? String,
                  let status = AddressStatus(rawValue:rawStatus) else { return }
            let reaction: WolfySemanticState
            switch status {
            case .appointment: reaction = .appointment
            case .hotLead: reaction = .lead
            case .talked, .futureSeller: reaction = .encouraging
            default: reaction = .wave
            }
            character.trigger(reaction)
            withAnimation { reactingToHome = true }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.55) {
                withAnimation { reactingToHome = false }
            }
        }
    }
}

struct WolfyDenView: View {
    @ObservedObject var economy: WolfyEconomyStore
    @StateObject private var character = WolfyCharacterController()
    var lifetimeDoors: Int? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: WolfyAccessoryCategory?
    @State private var equippedIDs:[String:String]=[:]
    @State private var message:String?
    @State private var showColors=false
    private var stage:Int { WolfyProgression.growthStage(doors:lifetimeDoors ?? 0) }
    var body: some View {
        NavigationStack {
            VStack(spacing:10) {
                HStack(spacing:8) {
                    if !showColors { categoryRail(leading:true) }
                    WolfyCharacterView(controller:character).frame(maxWidth:.infinity).frame(height:showColors ? 270 : 340)
                    if !showColors { categoryRail(leading:false) }
                }.frame(maxHeight:showColors ? 290 : 380)
                if let selectedCategory {
                    accessoryControls(selectedCategory)
                } else if showColors {
                    colorControls
                } else {
                    Text("\(WolfyProgression.growthStages[stage-1]) · Stage \(stage) of 5").font(.title3.bold())
                    Text("\((lifetimeDoors ?? 0).formatted()) lifetime doors").font(.subheadline).foregroundStyle(.secondary)
                    if let remaining=WolfyProgression.doorsUntilNextStage(doors:lifetimeDoors ?? 0) {
                        ProgressView(value:Double(max(0,(lifetimeDoors ?? 0)-WolfyProgression.growthDoorThresholds[stage-1])),total:Double(WolfyProgression.growthDoorThresholds[stage]-WolfyProgression.growthDoorThresholds[stage-1])).tint(.primary)
                        Text("\(remaining.formatted()) doors to the next stage").font(.caption).foregroundStyle(.secondary)
                    } else { Text("All five stages reached").font(.caption).foregroundStyle(.secondary) }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength:0)
            }.padding(.horizontal,12).padding(.top,18)
            .navigationTitle(selectedCategory?.title ?? (showColors ? "Wolf Colors" : "Customize Wolf")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { if selectedCategory != nil { selectedCategory=nil } else if showColors { showColors=false } else { dismiss() } } } }
            .task {
                if economy.snapshot == nil { await economy.refresh() }
                character.configureAppearance(user:economy.user,workspace:economy.workspace)
                character.setGrowthStage(stage)
                await character.load()
                await character.restore(economy.snapshot,equipment:economy.effectiveEquipment,catalog:economy.catalog)
                equippedIDs=economy.effectiveEquipment
            }
        }
    }
    private var colorControls: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                colorSection(title:"Fur",selected:character.appearance.fur,choices:[.classic,.silver,.charcoal,.brown,.arctic,.auburn]) { color in
                    var value=character.appearance;value.fur=color;setAppearance(value)
                }
                colorSection(title:"Eyes",selected:character.appearance.eyes,choices:[.amber,.blue,.green,.violet]) { color in
                    var value=character.appearance;value.eyes=color;setAppearance(value)
                }
                colorSection(title:"Nose",selected:character.appearance.nose,choices:[.black,.darkBrown]) { color in
                    var value=character.appearance;value.nose=color;setAppearance(value)
                }
                Button("Reset to Base") { setAppearance(WolfyAppearance()) }
                    .buttonStyle(.bordered).frame(maxWidth:.infinity,alignment:.center).padding(.top,8)
            }.padding(.horizontal,16).padding(.vertical,8)
        }
    }
    private func setAppearance(_ value:WolfyAppearance) {
        character.setAppearance(value)
    }
    private func colorSection(title:String,selected:WolfyColor,choices:[WolfyColor],onSelect:@escaping (WolfyColor)->Void) -> some View {
        VStack(alignment:.leading,spacing:10) {
            Text(title).font(.headline)
            HStack(spacing:15) {
                ForEach(choices) { color in
                    Button { onSelect(color) } label: {
                        VStack(spacing:5) {
                            Circle().fill(Color(uiColor:color.uiColor)).frame(width:34,height:34)
                                .overlay(Circle().stroke(selected==color ? Color.primary : Color.secondary.opacity(0.25),lineWidth:selected==color ? 3 : 1))
                            Text(color.title).font(.caption2).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("\(title): \(color.title)")
                }
            }
        }
    }
    private func categoryRail(leading:Bool) -> some View {
        let categories=leading ? Array(WolfyAccessoryCategory.all.prefix(5)) : Array(WolfyAccessoryCategory.all.dropFirst(5))
        return VStack(spacing:8) {
            ForEach(categories) { category in
                Button {
                    if category.key == "colors" { showColors=true; selectedCategory=nil }
                    else { selectedCategory=category }
                } label: {
                    VStack(spacing:4) {
                        Image(systemName:category.icon).font(.system(size:22,weight:.medium)).frame(width:48,height:48).background(.quaternary,in:Circle())
                        Text(category.title).font(.system(size:10,weight:.medium)).lineLimit(1)
                    }.foregroundStyle(.primary)
                }.buttonStyle(.plain).accessibilityLabel("Customize \(category.title)")
            }
        }.frame(width:58)
    }
    private func accessoryControls(_ category:WolfyAccessoryCategory) -> some View {
            ScrollView {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:140),spacing:12)],spacing:12) {
                    ForEach(items(in:category)) { item in
                        Button { apply(item) } label: {
                            VStack(alignment:.leading,spacing:8) {
                                Group {
                                    if let url=WolfyAssetLoader.url("accessory_\(item.id).png"),let image=UIImage(contentsOfFile:url.path) {
                                        Image(uiImage:image).resizable().scaledToFit().padding(8)
                                    } else { Image(systemName:category.icon).resizable().scaledToFit().padding(30).foregroundStyle(.secondary) }
                                }.frame(height:122).frame(maxWidth:.infinity).background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:16))
                                HStack(spacing:4) {
                                    Text(item.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Spacer(minLength:0)
                                    if equippedIDs[category.key]==item.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }
                                }.foregroundStyle(.primary)
                                Text(equippedIDs[category.key]==item.id ? "Tap to remove" : "Tap to wear").font(.caption).foregroundStyle(.secondary)
                            }.padding(10).background(.background,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.quaternary))
                        }.buttonStyle(.plain)
                    }
                }.padding()
            }
    }
    private func items(in category:WolfyAccessoryCategory)->[WolfyCatalogItem] {
        economy.catalog.filter { item in
            item.render_kind=="model3d" && item.asset != nil &&
            (item.category==category.key || category.key=="face" && item.category=="ears")
        }.sorted { $0.name < $1.name }
    }
    private func apply(_ item:WolfyCatalogItem) {
        Task {
            do {
                if equippedIDs[item.category]==item.id {
                    try await character.preview(item,enabled:false)
                    equippedIDs.removeValue(forKey:item.category)
                    try await economy.equip(item,enabled:false)
                    message="\(item.name) removed."
                } else {
                    try await character.preview(item)
                    equippedIDs[item.category]=item.id
                    try await economy.equip(item,enabled:true)
                    message="\(item.name) added to your wolf."
                    character.trigger(.customizing)
                }
                WolfyFeedback.perform()
            } catch { message="Preview updated. Sync will retry: \(error.localizedDescription)" }
        }
    }
}

private struct WolfyAccessoryCategory:Identifiable {
    let key:String;let title:String;let icon:String
    var id:String { key }
    static let all=[
        Self(key:"head",title:"Head",icon:"hat.cap.fill"),Self(key:"face",title:"Face",icon:"eyeglasses"),
        Self(key:"neck",title:"Neck",icon:"circle.dashed"),Self(key:"outerwear",title:"Clothes",icon:"tshirt.fill"),
        Self(key:"back",title:"Back",icon:"backpack.fill"),
        Self(key:"waist",title:"Waist",icon:"rectangle.split.3x1"),Self(key:"feet",title:"Shoes",icon:"shoe.2.fill"),
        Self(key:"hands",title:"Hands",icon:"hand.raised.fingers.spread.fill"),Self(key:"auras",title:"Effects",icon:"sparkles"),
        Self(key:"colors",title:"Colors",icon:"paintpalette.fill")]
}
