import SwiftUI
import RealityKit
import Combine
import CryptoKit
import OSLog

@MainActor final class WolfyAssetLoader {
    static let shared = WolfyAssetLoader()
    private var cache: [String: Entity] = [:]
    private var order: [String] = []
    let manifest: WolfyAssetManifest?
    private let log = Logger(subsystem: "WolfGrid", category: "WolfyAssets")
    init() {
        manifest = Self.url("wolfy_manifest.json").flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(WolfyAssetManifest.self,from:$0) }
    }
    static func url(_ name: String) -> URL? {
        guard !name.contains("/"), !name.contains("..") else { return nil }
        let path = name as NSString
        return Bundle.main.url(forResource:path.deletingPathExtension,withExtension:path.pathExtension,subdirectory:"Wolfy")
            ?? Bundle.main.url(forResource:path.deletingPathExtension,withExtension:path.pathExtension)
    }
    func load(_ name: String) async throws -> Entity {
        if let cached = cache[name] { return cached.clone(recursive: true) }
        guard let manifest, manifest.compatibility == "wolfy-v1", let info = manifest.files[name] else { throw CocoaError(.fileNoSuchFile) }
        let url: URL
        if let bundled=Self.url(name) { url=bundled }
        else { url=try await WolfyAssetDownloadCache.shared.file(name:name,version:manifest.version,info:info) }
        let start = Date()
        let valid = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf:url, options:.mappedIfSafe)
            return data.count == info.bytes && SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() == info.sha256
        }.value
        guard valid else { throw CocoaError(.fileReadCorruptFile) }
        let entity: Entity
        if #available(iOS 18.0, *) { entity = try await Entity(contentsOf:url) }
        else {
            var loaded: Entity?
            for try await result in Entity.loadAsync(contentsOf:url).values { loaded = result; break }
            guard let loaded else { throw CocoaError(.fileReadUnknown) }; entity = loaded
        }
        cache[name] = entity; order.append(name)
        while order.count > 4 { cache.removeValue(forKey:order.removeFirst()) }
        log.info("Asset loaded in \(Date().timeIntervalSince(start), privacy: .public)s")
        return entity.clone(recursive:true)
    }
    func reset() { cache.removeAll(); order.removeAll() }
}

@MainActor final class WolfyCharacterController: ObservableObject {
    @Published var ready = false
    @Published var failed = false
    @Published var description = "Wolfy is resting"
    let stage = Entity()
    private(set) var character: Entity?
    private var baseTask: Task<Entity,Error>?
    private var equipment: [String: Entity] = [:]
    private var playback: [AnimationPlaybackController] = []
    private var machine = WolfyCharacterStateMachine()
    private var animationTask: Task<Void,Never>?
    private var idleTask: Task<Void,Never>?
    private var equipmentIDs: [String:String] = [:]
    private var growthStage = 1
    private var growthRevision = UUID()
    private var idle: WolfySemanticState = .neutral
    private var reduced = false
    private var revision = UUID()
    private var platform: ModelEntity?
    private let camera = PerspectiveCamera()
    private let compactFraming: Bool
    @Published private(set) var appearance = WolfyAppearance()
    private var appearanceKey = "wolfy.appearance.default"
    private var appearanceScope: (user:UUID, workspace:UUID)?
    private var baseMaterials: [any RealityKit.Material] = []
    private var log = Logger(subsystem:"WolfGrid",category:"WolfyCharacter")
    init(compactFraming: Bool = false) {
        self.compactFraming = compactFraming
        let mesh:MeshResource
        if #available(iOS 18.0, *) { mesh = .generateCylinder(height:0.035,radius:0.48) }
        else { mesh = .generateBox(width:0.9,height:0.035,depth:0.9) }
        let platform=ModelEntity(mesh:mesh,materials:[SimpleMaterial(color:.darkGray,isMetallic:false)])
        platform.position.y = -0.025
        self.platform=platform;stage.addChild(platform)
        let light = DirectionalLight(); light.light.intensity = 2500
        light.look(at:[0,1,0],from:[-3,4,3],relativeTo:nil);stage.addChild(light)
        let fill = PointLight();fill.light.intensity=500;fill.position=[2,2,2];stage.addChild(fill)
        camera.camera.fieldOfViewInDegrees=36
        camera.look(at:[0,1.1,0],from:[0,1.15,4.5],relativeTo:nil);stage.addChild(camera)
    }
    func load() async {
        guard character == nil else { ready=true;return }
        do {
            let task: Task<Entity,Error>
            if let existing=baseTask { task=existing }
            else {
                task=Task { try await WolfyAssetLoader.shared.load(self.stageAsset(self.growthStage)) }
                baseTask=task
            }
            let model=try await task.value
            guard !Task.isCancelled, character == nil else { return }
            baseTask=nil
            character=model
            hideEmbeddedAccessories(in:model)
            rememberBaseMaterials(in:model)
            stage.addChild(model);ready=true;failed=false
            for id in equipmentIDs.values { setEmbeddedAccessory(id, enabled: true, in: model) }
            applyAppearance()
            updateCompactFraming()
            await animate(idle)
        } catch { baseTask=nil;failed=true;log.error("Base asset unavailable") }
    }
    func setMood(_ mood: WolfySemanticState, reduceMotion: Bool) {
        idle=mood;reduced=reduceMotion
        if reduceMotion { stopPlayback() }
        guard machine.request(mood,duration:0) else { return }
        animationTask?.cancel()
        animationTask=Task { await animate(mood) }
        idleTask?.cancel()
        idleTask=Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for:.seconds(Int.random(in:12...20))) } catch { return }
                guard let self else { return }
                if self.idle == .neutral && Date() >= self.machine.expires {
                    await self.playClip(["idle_neutral","look_around","idle_happy"].randomElement()!)
                }
            }
        }
    }
    func trigger(_ state: WolfySemanticState, eventID: String? = nil) {
        guard machine.request(state,eventID:eventID) else { return }
        animationTask?.cancel()
        animationTask=Task {
            await animate(state)
            try? await Task.sleep(for:.seconds(3))
            guard !Task.isCancelled else { return }
            await animate(idle)
        }
    }
    func laboratoryClip(_ name: String) { animationTask?.cancel();animationTask=Task { await playClip(name) } }
    private func animate(_ state: WolfySemanticState) async {
        description = "Wolfy: \(state.label)"
        await playClip(state.rawValue)
    }
    private func playClip(_ name: String) async {
        guard let character else { return }
        if reduced || ProcessInfo.processInfo.isLowPowerModeEnabled { stopPlayback();return }
        if growthStage > 0 {
            guard let animation=firstAnimation(character) else { return }
            let current=character.playAnimation(animation.repeat(),transitionDuration:0.25,startsPaused:false)
            let previous=playback;playback=[current]
            Task { try? await Task.sleep(for:.milliseconds(300));previous.forEach{$0.stop()} }
            return
        }
        guard let clip=WolfyAssetLoader.shared.manifest?.animations.first(where:{$0.name==name}) else { return }
        let ticket=UUID();revision=ticket
        do {
            let source=try await WolfyAssetLoader.shared.load(clip.file)
            guard !Task.isCancelled, ticket==revision else { return }
            guard let animation=firstAnimation(source) else { log.error("Named clip contains no animation");return }
            // Matching master skeleton paths allow one animation to drive base and fitted accessories.
            let resource=clip.loop ? animation.repeat() : animation
            let previous=playback
            playback = [character.playAnimation(resource,transitionDuration:0.25,startsPaused:false)]
            for entity in equipment.values { playback.append(entity.playAnimation(resource,transitionDuration:0.25,startsPaused:false)) }
            Task { try? await Task.sleep(for:.milliseconds(300));previous.forEach{$0.stop()} }
        } catch { log.error("Animation load failed") }
    }
    private func firstAnimation(_ entity: Entity) -> AnimationResource? {
        if let animation=entity.availableAnimations.first { return animation }
        for child in entity.children { if let animation=firstAnimation(child) { return animation } }
        return nil
    }
    func restore(_ snapshot: WolfySnapshot?, equipment desired: [String:String], catalog: [WolfyCatalogItem]? = nil) async {
        for category in Array(equipmentIDs.keys) where desired[category] != equipmentIDs[category] {
            if let id=equipmentIDs[category],let character { setEmbeddedAccessory(id,enabled:false,in:character) }
            equipment.removeValue(forKey:category);equipmentIDs.removeValue(forKey:category)
        }
        for (category,id) in desired where equipmentIDs[category] != id {
            if let item=(catalog ?? snapshot?.catalog ?? []).first(where:{$0.id==id}) { try? await preview(item) }
        }
        updateCompactFraming()
    }
    func preview(_ item: WolfyCatalogItem, enabled: Bool = true) async throws {
        guard let character else { throw CocoaError(.fileReadUnknown) }
        if let previous=equipmentIDs[item.category] { setEmbeddedAccessory(previous,enabled:false,in:character) }
        guard enabled else { equipmentIDs.removeValue(forKey:item.category); return }
        guard setEmbeddedAccessory(item.id,enabled:true,in:character) else { throw CocoaError(.fileNoSuchFile) }
        equipmentIDs[item.category]=item.id
    }
    func setLevel(_ level:Int) {
        let color:UIColor = level>=100 ? .cyan : level>=50 ? .systemYellow : level>=25 ? .systemBlue : level>=10 ? .systemGray : .darkGray
        platform?.model?.materials=[SimpleMaterial(color:color,isMetallic:level>=50)]
    }
    func setGrowthStage(_ stage:Int) {
        let next = min(5,max(1,stage))
        growthStage=next
        let colors:[UIColor] = [.darkGray,.systemTeal,.systemBlue,.systemPurple,.systemYellow]
        platform?.model?.materials=[SimpleMaterial(color:colors[next-1],isMetallic:next>=4)]
        guard character != nil else { return }
        let ticket=UUID();growthRevision=ticket
        Task { [weak self] in
            guard let self else { return }
            do {
                let nextCharacter=try await WolfyAssetLoader.shared.load(self.stageAsset(next))
                guard ticket==self.growthRevision else { return }
                self.stopPlayback()
                self.character?.removeFromParent()
                self.character=nextCharacter
                self.hideEmbeddedAccessories(in:nextCharacter)
                self.rememberBaseMaterials(in:nextCharacter)
                self.equipment.removeAll()
                self.stage.addChild(nextCharacter)
                for (category,id) in self.equipmentIDs where self.setEmbeddedAccessory(id,enabled:true,in:nextCharacter) {
                    if let item=nextCharacter.findEntity(named:"wolfy_item_\(id)") { self.equipment[category]=item }
                }
                self.ready=true;self.failed=false
                self.applyAppearance()
                self.updateCompactFraming()
                await self.animate(self.idle)
            } catch {
                guard ticket==self.growthRevision else { return }
                self.failed=true;self.log.error("Growth stage asset unavailable")
            }
        }
    }
    private func updateCompactFraming() {
        guard compactFraming, let character else { return }
        var bounds = character.visualBounds(relativeTo: stage, excludeInactive: true)
        if let platform { bounds.formUnion(platform.visualBounds(relativeTo: stage)) }
        let extent = bounds.extents
        guard extent.x.isFinite, extent.y.isFinite, extent.z.isFinite,
              max(extent.x, extent.y) > 0 else { return }
        // Home uses a square viewport. Fit the visible wolf and platform with a small margin.
        let distance = max(extent.x, extent.y) * 0.55 / tan(Float.pi / 10) + extent.z * 0.5
        camera.look(at: bounds.center, from: bounds.center + SIMD3<Float>(0, 0, distance), relativeTo: stage)
    }
    private func stageAsset(_ stage:Int) -> String {
        let key=["pup","young","street","alpha","legend"][min(4,max(0,stage-1))]
        return WolfyAssetLoader.shared.manifest?.growthStages?[key] ?? "wolfy_base.usdz"
    }
    func configureAppearance(user:UUID,workspace:UUID) {
        appearanceKey="wolfy.appearance.\(workspace).\(user)"
        appearanceScope=(user,workspace)
        appearance=WolfyAppearance.saved(user:user,workspace:workspace)
        applyAppearance()
    }
    func setAppearance(_ value:WolfyAppearance) {
        let value=value.normalized()
        appearance=value
        if let appearanceScope { value.save(user:appearanceScope.user,workspace:appearanceScope.workspace) }
        else if let data=try? JSONEncoder().encode(value) { UserDefaults.standard.set(data,forKey:appearanceKey) }
        applyAppearance()
        NotificationCenter.default.post(name:.wolfyWardrobeDidChange,object:nil)
    }
    private func rememberBaseMaterials(in root:Entity) {
        baseMaterials=(root.findEntity(named:"Wolfy") as? ModelEntity)?.model?.materials ?? []
    }
    private func applyAppearance() {
        guard let character,let body=character.findEntity(named:"Wolfy") as? ModelEntity,
              !baseMaterials.isEmpty else { return }
        body.model?.materials=baseMaterials.map { material in
            guard var pbr=material as? PhysicallyBasedMaterial else { return material }
            guard let components=pbr.baseColor.tint.cgColor.components,components.count>=3 else { return material }
            let r=components[0],g=components[1],b=components[2]
            func matches(_ red:CGFloat,_ green:CGFloat,_ blue:CGFloat) -> Bool {
                abs(r-red)<0.012 && abs(g-green)<0.012 && abs(b-blue)<0.012
            }
            let color:UIColor?
            if matches(0.8,0.8,0.8) || matches(0.79,0.85,0.84) || matches(0.2,0.255,0.3) {
                color=appearance.fur == .classic ? UIColor(red:r,green:g,blue:b,alpha:1) : appearance.fur.uiColor
            } else if matches(1,0.56,0.07) {
                color=appearance.eyes == .amber ? UIColor(red:r,green:g,blue:b,alpha:1) : appearance.eyes.uiColor
            } else if matches(0.065,0.078,0.095) {
                color=appearance.nose == .black ? UIColor(red:r,green:g,blue:b,alpha:1) : appearance.nose.uiColor
            } else { color=nil }
            if let color { pbr.baseColor.tint=color }
            return pbr
        }
    }
    private func hideEmbeddedAccessories(in root:Entity) {
        for child in root.children {
            if child.name.hasPrefix("wolfy_item_") { child.isEnabled=false }
            hideEmbeddedAccessories(in:child)
        }
    }
    @discardableResult private func setEmbeddedAccessory(_ id:String,enabled:Bool,in root:Entity) -> Bool {
        guard let entity=root.findEntity(named:"wolfy_item_\(id)") else { return false }
        entity.isEnabled=enabled
        return true
    }
    func rotate(_ radians: Float) {
        character?.orientation=simd_quatf(angle:radians,axis:[0,1,0])
    }
    private func stopPlayback() { playback.forEach{$0.stop()};playback.removeAll() }
    func pause() { idleTask?.cancel();animationTask?.cancel();revision=UUID();stopPlayback() }
}

struct WolfyCharacterView: View {
    @ObservedObject var controller: WolfyCharacterController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    var mood: WolfySemanticState = .neutral
    var forceReducedMotion = false
    @State private var rotation: Float = 0
    var body: some View {
        ZStack {
            if !controller.failed {
                if #available(iOS 18.0, *) {
                    RealityView { content in
                        content.camera = .virtual
                        content.add(controller.stage)
                        await controller.load()
                    }
                } else { WolfyLegacyRealityView(controller:controller).task { await controller.load() } }
                if !controller.ready { ProgressView("Loading Wolfy") }
            } else { Image(systemName:"pawprint.fill").font(.system(size:64)).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children:.ignore).accessibilityLabel(controller.description)
        .gesture(DragGesture().onChanged { value in controller.rotate(rotation + Float(value.translation.width)/120) }.onEnded { value in rotation += Float(value.translation.width)/120 })
        .onAppear { controller.setMood(mood,reduceMotion:reduceMotion || forceReducedMotion) }
        .onChange(of:mood) { _,value in controller.setMood(value,reduceMotion:reduceMotion || forceReducedMotion) }
        .onChange(of:forceReducedMotion) { _,value in controller.setMood(mood,reduceMotion:reduceMotion || value) }
        .onChange(of:reduceMotion) { _,value in controller.setMood(mood,reduceMotion:value) }
        .onChange(of:phase) { _,value in if value != .active { controller.pause() } else { controller.setMood(mood,reduceMotion:reduceMotion || forceReducedMotion) } }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)) { _ in WolfyAssetLoader.shared.reset() }
        .onDisappear { controller.pause() }
    }
}
private struct WolfyLegacyRealityView: UIViewRepresentable {
    let controller: WolfyCharacterController
    func makeUIView(context:Context) -> ARView {
        let view=ARView(frame:.zero,cameraMode:.nonAR,automaticallyConfigureSession:false)
        let anchor=AnchorEntity(world:.zero);anchor.addChild(controller.stage);view.scene.addAnchor(anchor)
        view.environment.background = .color(.clear)
        return view
    }
    func updateUIView(_ uiView:ARView,context:Context) {}
    static func dismantleUIView(_ uiView:ARView,coordinator:()) { uiView.scene.anchors.removeAll() }
}
