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
    private var baseTask: (stage: Int, task: Task<Entity,Error>)?
    private var equipment: [String: Entity] = [:]
    private var playback: [AnimationPlaybackController] = []
    private var playingGrowthReaction = false
    private var machine = WolfyCharacterStateMachine()
    private var animationTask: Task<Void,Never>?
    private var equipmentIDs: [String:String] = [:]
    private var growthStage = 1
    private var growthRevision = UUID()
    private var idle: WolfySemanticState = .neutral
    private var motionPaused = true
    private var revision = UUID()
    private var platform: ModelEntity?
    private let camera = PerspectiveCamera()
    private let compactFraming: Bool
    @Published private(set) var appearance = WolfyAppearance()
    private var appearanceKey = "wolfy.appearance.default"
    private var appearanceScope: (user:UUID, workspace:UUID)?
    private var baseMaterials: [any RealityKit.Material] = []
    private static let coatTextures: [WolfyColor: TextureResource] = Dictionary(uniqueKeysWithValues:
        WolfyColor.allCases.compactMap { color in
            guard let palette = color.coatPalette,
                  let texture = coatTexture(dark:palette.dark,light:palette.light) else { return nil }
            return (color, texture)
        })

    private static func coatTexture(dark: [CGFloat], light: [CGFloat]) -> TextureResource? {
        let width = 256
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let linearSpace = CGColorSpace(name: CGColorSpace.linearSRGB),
              let darkColor = CGColor(colorSpace: linearSpace, components: dark),
              let lightColor = CGColor(colorSpace: linearSpace, components: light),
              let context = CGContext(data:nil,width:width,height:2,bitsPerComponent:8,bytesPerRow:0,
                                      space:colorSpace,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue),
              let gradient = CGGradient(colorsSpace: linearSpace, colors: [darkColor, lightColor] as CFArray,
                                        locations: nil) else { return nil }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: CGFloat(width) - 0.5, y: 0),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        guard let image = context.makeImage() else { return nil }
        let options = TextureResource.CreateOptions(semantic:.color)
        if #available(iOS 18.0, *) { return try? TextureResource(image:image,options:options) }
        return try? TextureResource.generate(from:image,options:options)
    }
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
        let requestedStage = growthStage
        do {
            let task: Task<Entity,Error>
            if let existing=baseTask, existing.stage == requestedStage { task=existing.task }
            else {
                task=Task { try await WolfyAssetLoader.shared.load(self.stageAsset(requestedStage)) }
                baseTask=(requestedStage,task)
            }
            let model=try await task.value
            guard !Task.isCancelled, character == nil else { return }
            guard requestedStage == growthStage else { await load(); return }
            baseTask=nil
            character=model
            hideEmbeddedAccessories(in:model)
            rememberBaseMaterials(in:model)
            stage.addChild(model);ready=true;failed=false
            for id in equipmentIDs.values { setEmbeddedAccessory(id, enabled: true, in: model) }
            applyAppearance()
            updateCompactFraming()
            await animate(idle)
        } catch {
            guard !Task.isCancelled, character == nil else { return }
            guard requestedStage == growthStage else { await load(); return }
            baseTask=nil;failed=true;log.error("Base asset unavailable")
        }
    }
    func setMood(_ mood: WolfySemanticState, motionPaused: Bool) {
        idle=mood
        if motionPaused { pause(); return }
        let resuming = self.motionPaused
        self.motionPaused=false
        guard machine.request(mood,duration:0) || resuming else { return }
        animationTask?.cancel()
        animationTask=Task { await animate(mood) }
    }
    func trigger(_ state: WolfySemanticState, eventID: String? = nil) {
        guard !motionPaused, machine.request(state,eventID:eventID) else { return }
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
        guard !motionPaused, let character else { return }
        if growthStage > 0 {
            let reactions: Set<String> = ["celebrate_lead", "celebrate_appointment", "celebrate_sale", "goal_completed", "rank_up", "level_up", "play", "wave", "equip_item"]
            let isReaction = reactions.contains(name)
            guard isReaction || playingGrowthReaction || playback.isEmpty else { return }
            let ticket = UUID(); revision = ticket
            var source = character
            if isReaction {
                let file = stageAsset(growthStage).replacingOccurrences(of: ".usdz", with: "_celebrate.usdz")
                do { source = try await WolfyAssetLoader.shared.load(file) }
                catch { return }
            }
            guard !Task.isCancelled, !motionPaused, ticket == revision,
                  self.character === character,
                  let animation = source.availableAnimations.first(where: { $0.name == "global scene animation" }) ?? firstAnimation(source) else { return }
            stopPlayback()
            playingGrowthReaction = isReaction
            playback = [character.playAnimation(isReaction ? animation : animation.repeat(), transitionDuration:0.3)]
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
        guard desired != equipmentIDs else { return }
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
        guard next != growthStage else { return }
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
        camera.look(at: bounds.center, from: bounds.center + SIMD3<Float>(distance * 0.33, distance * 0.09, distance), relativeTo: stage)
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
                if matches(0.8,0.8,0.8), let texture = Self.coatTextures[appearance.fur] {
                    pbr.baseColor = .init(tint:.white,texture:.init(texture))
                    return pbr
                }
                // Separate ears, brows and light details match the coat endpoints.
                if let swatch = appearance.fur.coatSwatch {
                    color = matches(0.79,0.85,0.84) ? swatch[1] : swatch[0]
                } else { color = appearance.fur.uiColor }
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
            if child.name.hasPrefix("wolfy_item_") {
                child.isEnabled=false
            } else {
                hideEmbeddedAccessories(in:child)
            }
        }
    }
    @discardableResult private func setEmbeddedAccessory(_ id:String,enabled:Bool,in root:Entity) -> Bool {
        guard let entity=root.findEntity(named:"wolfy_item_\(id)") else { return false }
        // USDZ exports each item as an Xform with a same-named Mesh child.
        // Both may already be disabled in a loaded model, so restore the whole subtree.
        func setEnabled(_ node:Entity) {
            node.isEnabled=enabled
            for child in node.children { setEnabled(child) }
        }
        setEnabled(entity)
        return true
    }
    func rotate(_ radians: Float) {
        character?.orientation=simd_quatf(angle:radians,axis:[0,1,0])
    }
    private func stopPlayback() { playback.forEach{$0.stop()};playback.removeAll();playingGrowthReaction=false }
    func pause() { motionPaused=true;animationTask?.cancel();revision=UUID();stopPlayback() }
}

struct WolfyCharacterView: View {
    @ObservedObject var controller: WolfyCharacterController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    var mood: WolfySemanticState = .neutral
    var forceReducedMotion = false
    var suspended = false
    @State private var rotation: Float = 0
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var motionPaused: Bool {
        suspended || reduceMotion || forceReducedMotion || lowPower || phase != .active
    }
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
        .onAppear { controller.setMood(mood,motionPaused:motionPaused) }
        .onChange(of:mood) { _,value in controller.setMood(value,motionPaused:motionPaused) }
        .onChange(of:motionPaused) { _,value in controller.setMood(mood,motionPaused:value) }
        .onReceive(NotificationCenter.default.publisher(for:.NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
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
