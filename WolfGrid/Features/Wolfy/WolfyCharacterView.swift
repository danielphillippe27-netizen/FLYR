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
    private var idle: WolfySemanticState = .neutral
    private var reduced = false
    private var revision = UUID()
    private var platform: ModelEntity?
    private var log = Logger(subsystem:"WolfGrid",category:"WolfyCharacter")
    init() {
        let mesh:MeshResource
        if #available(iOS 18.0, *) { mesh = .generateCylinder(height:0.035,radius:0.48) }
        else { mesh = .generateBox(width:0.9,height:0.035,depth:0.9) }
        let platform=ModelEntity(mesh:mesh,materials:[SimpleMaterial(color:.darkGray,isMetallic:false)])
        platform.position.y = -0.025
        self.platform=platform;stage.addChild(platform)
        let light = DirectionalLight(); light.light.intensity = 2500
        light.look(at:[0,1,0],from:[-3,4,3],relativeTo:nil);stage.addChild(light)
        let fill = PointLight();fill.light.intensity=500;fill.position=[2,2,2];stage.addChild(fill)
        let camera=PerspectiveCamera();camera.camera.fieldOfViewInDegrees=36
        camera.look(at:[0,1.1,0],from:[0,1.15,4.5],relativeTo:nil);stage.addChild(camera)
    }
    func load() async {
        guard character == nil else { ready=true;return }
        do {
            let task: Task<Entity,Error>
            if let existing=baseTask { task=existing }
            else {
                task=Task { try await WolfyAssetLoader.shared.load("wolfy_base.usdz") }
                baseTask=task
            }
            let model=try await task.value
            guard !Task.isCancelled, character == nil else { return }
            baseTask=nil
            character=model;stage.addChild(model);ready=true;failed=false
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
    func restore(_ snapshot: WolfySnapshot?, equipment desired: [String:String]) async {
        for category in Array(equipmentIDs.keys) where desired[category] != equipmentIDs[category] {
            equipment.removeValue(forKey:category)?.removeFromParent();equipmentIDs.removeValue(forKey:category)
        }
        for (category,id) in desired where equipmentIDs[category] != id {
            if let item=snapshot?.catalog?.first(where:{$0.id==id}) { try? await preview(item) }
        }
    }
    func preview(_ item: WolfyCatalogItem, enabled: Bool = true) async throws {
        guard let character else { throw CocoaError(.fileReadUnknown) }
        if !enabled { equipment.removeValue(forKey:item.category)?.removeFromParent();equipmentIDs.removeValue(forKey:item.category);return }
        guard let asset=item.asset else { equipment.removeValue(forKey:item.category)?.removeFromParent();equipmentIDs.removeValue(forKey:item.category);return }
        let loaded=try await WolfyAssetLoader.shared.load(asset)
        // Accessory exports use the identical master rig and bind pose, at the same origin.
        equipment.removeValue(forKey:item.category)?.removeFromParent()
        equipment[item.category]=loaded;equipmentIDs[item.category]=item.id;stage.addChild(loaded)
        loaded.transform=character.transform
        await animate(idle)
    }
    func setLevel(_ level:Int) {
        let color:UIColor = level>=100 ? .cyan : level>=50 ? .systemYellow : level>=25 ? .systemBlue : level>=10 ? .systemGray : .darkGray
        platform?.model?.materials=[SimpleMaterial(color:color,isMetallic:level>=50)]
    }
    func rotate(_ radians: Float) {
        character?.orientation=simd_quatf(angle:radians,axis:[0,1,0])
        for entity in equipment.values { entity.orientation=character?.orientation ?? simd_quatf() }
    }
    private func stopPlayback() { playback.forEach{$0.stop()};playback.removeAll() }
    func pause() { idleTask?.cancel();animationTask?.cancel();revision=UUID();stopPlayback() }
}

struct WolfyCharacterView: View {
    @ObservedObject var controller: WolfyCharacterController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @AppStorage("wolfy.3d") private var enabled = WolfyFeatureDefaults.enabled
    var mood: WolfySemanticState = .neutral
    var forceReducedMotion = false
    @State private var rotation: Float = 0
    var body: some View {
        ZStack {
            if enabled && !controller.failed {
                if #available(iOS 18.0, *) {
                    RealityView { content in
                        content.camera = .virtual
                        content.add(controller.stage)
                        await controller.load()
                    }
                } else { WolfyLegacyRealityView(controller:controller).task { await controller.load() } }
                if !controller.ready { ProgressView("Loading Wolfy") }
            } else {
                if let url=WolfyAssetLoader.url("wolfy_poster.png"), let image=UIImage(contentsOfFile:url.path) {
                    Image(uiImage:image).resizable().scaledToFit()
                } else { Image(systemName:"pawprint.fill").font(.system(size:64)).foregroundStyle(.secondary) }
            }
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
