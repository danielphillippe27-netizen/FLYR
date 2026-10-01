import SwiftUI
import MetalKit
import MapboxMaps
import Turf
import simd
import CryptoKit
import OSLog

/// Isolated first release gate. Uses Mapbox's depth attachment and terrain, never a screen overlay.
/// Prototype resources deliberately cannot be selected by the production character loader.
final class WolfyMapPrototypeRenderer: NSObject, CustomLayerHost {
    struct Manifest: Decodable {
        struct Clip: Decodable { let file: String; let duration: Double; let frames: Int }
        struct File: Decodable { let bytes: Int; let sha256: String }
        let version: Int; let prototype: Bool; let vertices: Int; let indices: Int
        let bones: [String]; let mesh: String; let clips: [String: Clip]; let files: [String: File]
    }
    private struct WardrobeManifest: Decodable {
        struct Item: Decodable { let vertexOffset: Int; let indexOffset: Int; let indexCount: Int }
        let version: Int; let mesh: String; let bytes: Int; let sha256: String; let items: [String:Item]
    }
    private struct StageResource {
        let manifest: Manifest
        let mesh: MTLBuffer
        let animation: [String: [Float]]
        let wardrobe: WardrobeManifest
        let wardrobeMesh: MTLBuffer
    }
    private let log = Logger(subsystem: "WolfGrid", category: "WolfyMapPrototype")
    private let lock = NSLock()
    private var selectedClip = "walk"
    private var clipStartedAt = CACurrentMediaTime()
    private var visible = true
    private var origin: CLLocationCoordinate2D
    private var heading: Double = 180
    private var minimumMapScale: Double = 0
    private var animated = true
    private let drawAboveBuildings: Bool
    private var ready = false
    var isReady: Bool { lock.lock(); defer { lock.unlock() }; return ready }
    private var pipeline: MTLRenderPipelineState?
    private var depth: MTLDepthStencilState?
    private var equippedItemIDs: [String] = []
    private var appearance = WolfyAppearance()
    private var growthStage = 1
    private var stages: [Int: StageResource] = [:]
    private var epoch = CACurrentMediaTime()
    private var frameCount = 0
    private var lastFrameIndex = -1
    var diagnostic: String { "frames=\(frameCount), animationFrame=\(lastFrameIndex), pipeline=\(pipeline != nil), failure=\(failure ?? "none")" }
    private(set) var failure: String?
    init(origin: CLLocationCoordinate2D, drawAboveBuildings: Bool = false) {
        self.origin = origin
        self.drawAboveBuildings = drawAboveBuildings
        super.init()
    }
    func select(_ clip: String) {
        lock.lock(); defer { lock.unlock() }
        if selectedClip != clip { selectedClip = clip; clipStartedAt = CACurrentMediaTime() }
    }
    func setVisible(_ value: Bool) { lock.lock(); visible = value; lock.unlock() }
    func setEquipment(_ equipment: [String:String]) {
        lock.lock(); equippedItemIDs = Array(equipment.values).sorted(); lock.unlock()
    }
    func setAppearance(_ value: WolfyAppearance) { lock.lock(); appearance=value; lock.unlock() }
    func setGrowthStage(_ value: Int) { lock.lock(); growthStage=min(5,max(1,value)); lock.unlock() }
    private static func color(_ color: WolfyColor, defaultColor: WolfyColor) -> SIMD4<Float> {
        guard color != defaultColor else { return .zero }
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        color.uiColor.getRed(&r,green:&g,blue:&b,alpha:&a)
        return SIMD4(Float(r),Float(g),Float(b),1)
    }
    /// Live campaign marker uses the same quadruped mesh as the map preview.
    func updateLocation(_ coordinate: CLLocationCoordinate2D, heading: Double?, speed: Double, animated: Bool) {
        lock.lock(); defer { lock.unlock() }
        origin = coordinate
        if let heading, heading.isFinite { self.heading = heading }
        let nextClip = speed >= 2.5 ? "run" : speed >= 0.5 ? "walk" : "idle"
        if selectedClip != nextClip { selectedClip = nextClip; clipStartedAt = CACurrentMediaTime() }
        minimumMapScale = 28
        self.animated = animated
    }
    private static func url(_ name: String) throws -> URL {
        guard name == (name as NSString).lastPathComponent,
              let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "WolfyV2")
                ?? Bundle.main.url(forResource: name, withExtension: nil) else { throw CocoaError(.fileNoSuchFile) }
        return url
    }
    func renderingWillStart(_ device: MTLDevice, colorPixelFormat: UInt, depthStencilPixelFormat: UInt) {
        do {
            func verified(_ name: String, in m: Manifest) throws -> Data {
                let d = try Data(contentsOf: Self.url(name))
                guard let info = m.files[name], d.count == info.bytes,
                      SHA256.hash(data: d).map({ String(format:"%02x",$0) }).joined() == info.sha256 else { throw CocoaError(.fileReadCorruptFile) }
                return d
            }
            for (index,name) in ["pup","young","street","alpha","legend"].enumerated() {
                let m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.url("\(name)-manifest.json")))
                guard m.version == 2, m.prototype, m.bones.count <= 64, m.vertices > 0, m.indices > 0 else { throw CocoaError(.fileReadCorruptFile) }
                let data = try verified(m.mesh, in:m)
                guard data.count == m.vertices * 64 + m.indices * 4,
                      let mesh = data.withUnsafeBytes({ bytes in device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count) }) else { throw CocoaError(.fileReadCorruptFile) }
                var clips: [String:[Float]] = [:]
                for (clipName,clip) in m.clips {
                    let bytes = try verified(clip.file, in:m)
                    guard clip.frames > 0, clip.duration > 0, bytes.count == clip.frames * m.bones.count * 64 else { throw CocoaError(.fileReadCorruptFile) }
                    clips[clipName] = bytes.withUnsafeBytes { Array($0.bindMemory(to:Float.self)) }
                }
                let wardrobe = try JSONDecoder().decode(WardrobeManifest.self, from: Data(contentsOf: Self.url("wardrobe-\(name)-manifest.json")))
                let wardrobeData = try Data(contentsOf: Self.url(wardrobe.mesh))
                guard wardrobe.version == 1, wardrobeData.count == wardrobe.bytes,
                      SHA256.hash(data:wardrobeData).map({ String(format:"%02x",$0) }).joined() == wardrobe.sha256,
                      wardrobe.items.values.allSatisfy({ $0.vertexOffset >= 0 && $0.indexOffset > $0.vertexOffset && $0.indexCount > 0 && $0.indexOffset + $0.indexCount * 4 <= wardrobeData.count }),
                      let wardrobeMesh = wardrobeData.withUnsafeBytes({ device.makeBuffer(bytes:$0.baseAddress!,length:$0.count) }) else { throw CocoaError(.fileReadCorruptFile) }
                stages[index+1] = StageResource(manifest:m,mesh:mesh,animation:clips,wardrobe:wardrobe,wardrobeMesh:wardrobeMesh)
            }
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = library.makeFunction(name: "wolfy_vertex")
            p.fragmentFunction = library.makeFunction(name: "wolfy_fragment")
            p.colorAttachments[0].pixelFormat = MTLPixelFormat(rawValue: colorPixelFormat)!
            p.depthAttachmentPixelFormat = MTLPixelFormat(rawValue: depthStencilPixelFormat)!
            p.stencilAttachmentPixelFormat = MTLPixelFormat(rawValue: depthStencilPixelFormat)!
            pipeline = try device.makeRenderPipelineState(descriptor: p)
            let d = MTLDepthStencilDescriptor(); d.depthCompareFunction = .lessEqual; d.isDepthWriteEnabled = true
            depth = device.makeDepthStencilState(descriptor: d)
            epoch = CACurrentMediaTime()
            lock.lock(); ready = true; lock.unlock()
        } catch {
            failure = "Prototype assets or Metal pipeline unavailable"
            log.error("Wolfy prototype failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    func render(_ parameters: CustomLayerRenderParameters, mtlCommandBuffer: MTLCommandBuffer, mtlRenderPassDescriptor: MTLRenderPassDescriptor) {
        lock.lock()
        let clipName = selectedClip, isVisible = visible, origin = origin, heading = heading
        let equippedItemIDs = equippedItemIDs, growthStage = growthStage
        let appearance = appearance
        let minimumMapScale = minimumMapScale, animated = animated
        let clipStartedAt = clipStartedAt
        lock.unlock()
        guard isVisible, let resource = stages[growthStage], let pipeline, let depth,
              let clip = resource.manifest.clips[clipName], let samples = resource.animation[clipName],
              let texture = mtlRenderPassDescriptor.colorAttachments[0].texture else { return }
        let m = resource.manifest, mesh = resource.mesh
        let progress = animated ? (CACurrentMediaTime() - clipStartedAt).truncatingRemainder(dividingBy: clip.duration) / clip.duration * Double(clip.frames) : 0
        let first = Int(progress) % clip.frames, second = (first + 1) % clip.frames
        frameCount += 1; lastFrameIndex = first
        let mix = Float(progress - Double(first)), stride = m.bones.count * 16
        var bones = [Float](repeating: 0, count: stride)
        for i in 0..<stride { bones[i] = samples[first * stride + i] * (1-mix) + samples[second * stride + i] * mix }
        // Double precision until the final matrix prevents street-scale Mercator jitter.
        let values = parameters.projectionMatrix.map(\.doubleValue)
        guard values.count == 16 else { return }
        var projection = matrix_identity_double4x4
        for c in 0..<4 { for r in 0..<4 { projection[c][r] = values[c*4+r] } }
        let projected = Projection.project(origin, zoomScale: CGFloat(pow(2, parameters.zoom)))
        let naturalScale = 1 / Projection.metersPerPoint(for: origin.latitude, zoom: CGFloat(parameters.zoom))
        // Keep the existing map-zoom response and minimum-size floor, then
        // apply the requested 1.5x avatar size uniformly at every zoom level.
        let scale = max(naturalScale, minimumMapScale) * 1.5
        // The source mesh faces negative Y; Mapbox's projected Y points south.
        let angle = (180 - heading) * Double.pi / 180
        var model = matrix_identity_double4x4
        model[0][0] = cos(angle) * scale; model[0][1] = -sin(angle) * scale
        model[1][0] = -sin(angle) * scale; model[1][1] = -cos(angle) * scale
        model[2][2] = scale / naturalScale
        model[3][0] = projected.x; model[3][1] = projected.y
        model[3][2] = parameters.elevationData?.getElevationFor(origin)?.doubleValue ?? 0
        let result = projection * model
        var mvp = matrix_identity_float4x4
        for c in 0..<4 { for r in 0..<4 { mvp[c][r] = Float(result[c][r]) } }
        guard let encoder = mtlCommandBuffer.makeRenderCommandEncoder(descriptor: mtlRenderPassDescriptor) else { return }
        encoder.label = "Wolfy prototype: skinned quadruped"
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(texture.width), height: Double(texture.height), znear: 0, zfar: 1))
        encoder.setRenderPipelineState(pipeline); encoder.setDepthStencilState(depth)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(mesh, offset: 0, index: 0)
        encoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.stride, index: 1)
        var foregroundDepth: Float = drawAboveBuildings ? 1 : 0
        encoder.setVertexBytes(&foregroundDepth, length: MemoryLayout<Float>.stride, index: 3)
        var furColor=Self.color(appearance.fur,defaultColor:.classic)
        var eyeColor=Self.color(appearance.eyes,defaultColor:.amber)
        var noseColor=Self.color(appearance.nose,defaultColor:.black)
        encoder.setVertexBytes(&furColor,length:MemoryLayout<SIMD4<Float>>.stride,index:4)
        encoder.setVertexBytes(&eyeColor,length:MemoryLayout<SIMD4<Float>>.stride,index:5)
        encoder.setVertexBytes(&noseColor,length:MemoryLayout<SIMD4<Float>>.stride,index:6)
        bones.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 2) }
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: m.indices, indexType: .uint32, indexBuffer: mesh, indexBufferOffset: m.vertices * 64)
        for id in equippedItemIDs {
            guard let item = resource.wardrobe.items[id] else { continue }
            encoder.setVertexBuffer(resource.wardrobeMesh, offset:item.vertexOffset, index:0)
            encoder.drawIndexedPrimitives(type:.triangle, indexCount:item.indexCount, indexType:.uint32,
                                          indexBuffer:resource.wardrobeMesh, indexBufferOffset:item.indexOffset)
        }
        encoder.endEncoding()
    }
    func renderingWillEnd() {
        lock.lock(); ready = false; lock.unlock()
        pipeline = nil; stages.removeAll()
    }
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position; float4 normal; float4 color; float4 joint; };
    struct Raster { float4 position [[position]]; float3 normal; float4 color; };
    vertex Raster wolfy_vertex(uint id [[vertex_id]], device const Vertex *vertices [[buffer(0)]],
                              constant float4x4 &mvp [[buffer(1)]], constant float4x4 *bones [[buffer(2)]],
                              constant float &foregroundDepth [[buffer(3)]],
                              constant float4 &furColor [[buffer(4)]], constant float4 &eyeColor [[buffer(5)]],
                              constant float4 &noseColor [[buffer(6)]]) {
        Vertex v = vertices[id];
        float4x4 skin = bones[uint(v.joint.x)] * (1.0-v.joint.z) + bones[uint(v.joint.y)] * v.joint.z;
        Raster out; out.position = mvp * skin * v.position;
        // Preserve self-depth while placing the local avatar in front of building depth.
        out.position.z *= mix(1.0, 0.00001, foregroundDepth);
        out.normal = normalize((skin * v.normal).xyz);
        float3 c=v.color.rgb;
        // Home's RealityKit character uses the light coat tint across its
        // continuous body surface. The Metal source encodes that same surface
        // as a dark-to-cream vertex gradient, so recolor the whole range.
        if (c.r>=.19 && c.r<=.81 && c.g>=.25 && c.g<=.87 && c.b>=.29 && c.b<=.87) {
            float3 coat = furColor.a>0 ? furColor.rgb : float3(.96,.97,.98);
            float marking = clamp((c.r-.20)/.59,0.0,1.0);
            c=mix(coat*.96,min(coat*1.04,float3(1.0)),marking);
        }
        if (eyeColor.a>0 && distance(c,float3(1,.56,.07))<.08) c=eyeColor.rgb;
        if (noseColor.a>0 && v.position.y<-.73 && distance(c,float3(.025,.035,.045))<.04) c=noseColor.rgb;
        out.color=float4(c,v.color.a); return out;
    }
    fragment float4 wolfy_fragment(Raster in [[stage_in]]) {
        float lighting = .76 + .24 * max(0.0, dot(normalize(in.normal),normalize(float3(-.5,-.6,1))));
        return float4(in.color.rgb * lighting,1);
    }
    """
}

#if DEBUG
struct WolfyMapPrototypeView: UIViewRepresentable {
    let clip: String
    let active: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MapView {
        let origin = CLLocationCoordinate2D(latitude: 43.65324, longitude: -79.3837)
        let campaignCheck = ProcessInfo.processInfo.arguments.contains("--campaign-wolf-verification")
        let map = DisplayLinkRecoveringMapView(frame: .zero, mapInitOptions: MapInitOptions(cameraOptions: CameraOptions(center: origin, zoom: campaignCheck ? 18.5 : 22, bearing: 20, pitch: 60), styleURI: .streets))
        context.coordinator.install(map, origin: origin)
        return map
    }
    func updateUIView(_ map: MapView, context: Context) { context.coordinator.renderer?.select(clip); context.coordinator.setActive(active) }
    static func dismantleUIView(_ map: MapView, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator: NSObject {
        weak var map: MapView?
        var renderer: WolfyMapPrototypeRenderer?
        private var campaignMarker: CampaignWolfLocationMarker?
        private var timer: CADisplayLink?
        private var loaded: AnyCancelable?
        private var captureTasks: [DispatchWorkItem] = []
        func install(_ map: MapView, origin: CLLocationCoordinate2D) {
            self.map = map; renderer = WolfyMapPrototypeRenderer(origin: origin)
            if let item = ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--map-accessory=")})?.replacingOccurrences(of:"--map-accessory=",with:"") {
                renderer?.setEquipment(["preview":item])
            }
            if ProcessInfo.processInfo.arguments.contains("--map-color-review") {
                renderer?.setAppearance(WolfyAppearance(fur:.arctic,eyes:.green,nose:.darkBrown))
            }
            loaded = map.mapboxMap.onStyleLoaded.observe { [weak self] _ in
                guard let self, let renderer = self.renderer else { return }
                do {
                    // Synthetic two-metre wall to exercise shared depth, never campaign geometry.
                    var source = GeoJSONSource(id: "wolfy-occlusion-source")
                    let ring = [(-0.000009,-0.000014),(0.000009,-0.000014),(0.000009,-0.000009),(-0.000009,-0.000009),(-0.000009,-0.000014)].map {
                        CLLocationCoordinate2D(latitude: origin.latitude + $0.1, longitude: origin.longitude + $0.0)
                    }
                    source.data = .feature(Feature(geometry: .polygon(Polygon([ring]))))
                    try map.mapboxMap.addSource(source)
                    var wall = FillExtrusionLayer(id: "wolfy-occlusion-wall", source: source.id)
                    wall.fillExtrusionHeight = .constant(2)
                    wall.fillExtrusionColor = .constant(StyleColor(.systemGray))
                    wall.fillExtrusionOpacity = .constant(ProcessInfo.processInfo.arguments.contains("--map-no-wall") ? 0 : 1)
                    try map.mapboxMap.addLayer(wall)
                    if ProcessInfo.processInfo.arguments.contains("--campaign-wolf-verification") {
                        var locationSource = GeoJSONSource(id: "verification-location")
                        locationSource.data = .featureCollection(FeatureCollection(features: []))
                        try map.mapboxMap.addSource(locationSource)
                        self.campaignMarker = CampaignWolfLocationMarker(mapView: map, sourceID: locationSource.id)
                        self.campaignMarker?.update(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), heading: 35, show: true)
                        map.mapboxMap.setCamera(to: CameraOptions(zoom: 18.5, pitch: 45))
                    } else {
                        try map.mapboxMap.addCustomLayer(withId: "wolfy-prototype", layerHost: renderer, layerPosition: .above(wall.id))
                    }
                }
                catch { print("Wolfy prototype layer failed: \(error)") }
                // Debug-only synthetic-map evidence; never captures an authenticated campaign.
                let turn = DispatchWorkItem { [weak self] in
                    self?.map?.mapboxMap.setCamera(to: CameraOptions(bearing: 180, pitch: 65))
                    self?.campaignMarker?.update(location: CLLocation(coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude + 0.00003), altitude: 0, horizontalAccuracy: 3, verticalAccuracy: 3, course: 90, speed: 1.2, timestamp: Date()), heading: 90, show: true)
                }
                self.captureTasks.append(turn)
                DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: turn)
                for (index, delay) in [8.0, 8.5, 12.0].enumerated() {
                    let task = DispatchWorkItem { [weak self] in
                        guard let self, let map = self.map else { return }

                        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        do {
                            let image = try map.snapshot(includeOverlays: true)
                            try image.pngData()?.write(to: directory.appendingPathComponent("wolfy-prototype-\(index).png"))
                            let status = self.campaignMarker?.diagnostic ?? self.renderer?.diagnostic ?? "Renderer missing"
                            try status.write(to: directory.appendingPathComponent("wolfy-prototype-status-\(index).txt"), atomically: true, encoding: .utf8)
                        } catch { print("Prototype capture failed: \(error)") }
                    }
                    self.captureTasks.append(task)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
                }
            }
            setActive(true)
        }
        func setActive(_ active: Bool) {
            renderer?.setVisible(active)
            if active && timer == nil {
                let link = CADisplayLink(target: self, selector: #selector(frame))
                link.preferredFramesPerSecond = 30; link.add(to: .main, forMode: .common); timer = link
            } else if !active { timer?.invalidate(); timer = nil }
        }
        @objc private func frame() { map?.mapboxMap.triggerRepaint() }
        func stop() { setActive(false); campaignMarker?.stop(); loaded?.cancel(); loaded = nil; captureTasks.forEach { $0.cancel() }; captureTasks.removeAll() }
        deinit { timer?.invalidate() }
    }
}
struct WolfyMapPrototypeEntryView: View {
    @State private var clip = "walk"
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(spacing: 0) {
            Text("Wolfy · Map Prototype").font(.headline).padding()
            Text("Synthetic position • quadruped rendering gate").font(.caption)
            WolfyMapPrototypeView(clip: clip, active: phase == .active)
            Picker("Animation", selection: $clip) {
                ForEach(["idle","walk","trot","run","sit","look_around","celebrate"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu).padding()
        }
    }
}
#endif
