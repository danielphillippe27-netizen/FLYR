#if DEBUG
import Foundation
import MetalKit
import MapboxMaps
import simd
import CryptoKit

/// Development renderer: shared stage resources, instanced draws and per-character pose buffers.
/// Draft art remains explicitly gated; this is not a production-art acceptance marker.
final class WolfyPackRendererV2: NSObject, CustomLayerHost {
    private struct Resource {
        let manifest: WolfyMapPrototypeRenderer.Manifest
        let mesh: MTLBuffer
        let animations: [String: [Float]]
    }
    private struct Instance { var mvp: simd_float4x4; var headingOpacity: SIMD4<Float> }
    private struct FrameBuffers { let instances: MTLBuffer; let bones: MTLBuffer }
    private let lock = NSLock()
    private var poses: [WolfyPackMotionV2.Pose] = []
    private var enabled = true
    private var resources: [WolfyStage: Resource] = [:]
    private var pipeline: MTLRenderPipelineState?
    private var depth: MTLDepthStencilState?
    private var buffers: [FrameBuffers] = []
    private var freeSlots = [0, 1, 2]
    private var loadedStages = 0
    private var submittedFrames = 0
    private var cpuTimes: [Double] = []
    private var failure: String?
    private let epoch = CACurrentMediaTime()
    func update(_ poses: [WolfyPackMotionV2.Pose], enabled: Bool) {
        lock.lock(); self.poses = Array(poses.filter { $0.detail != .marker }.prefix(8)); self.enabled = enabled; lock.unlock()
    }
    var diagnostic: String {
        lock.lock(); defer { lock.unlock() }
        let sorted = cpuTimes.sorted(), p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count-1,Int(Double(sorted.count)*0.95))]
        return "frames=\(submittedFrames), cpuEncodeP95ms=\(p95), stages=\(loadedStages), failure=\(failure ?? "none")"
    }
    func renderingWillStart(_ device: MTLDevice, colorPixelFormat: UInt, depthStencilPixelFormat: UInt) {
        do {
            func read(_ name: String) throws -> Data {
                guard name == (name as NSString).lastPathComponent,
                      let url = Bundle.main.url(forResource:name,withExtension:nil,subdirectory:"WolfyV2") ?? Bundle.main.url(forResource:name,withExtension:nil)
                else { throw CocoaError(.fileNoSuchFile) }
                return try Data(contentsOf:url)
            }
            for (stage,name) in zip(WolfyStage.allCases,["pup","young","street","alpha","legend"]) {
                let manifest = try JSONDecoder().decode(WolfyMapPrototypeRenderer.Manifest.self,from:read("\(name)-manifest.json"))
                guard manifest.prototype, manifest.version == 2, manifest.bones.count <= 64 else { throw CocoaError(.fileReadCorruptFile) }
                func checked(_ file: String) throws -> Data {
                    let bytes = try read(file)
                    guard let metadata = manifest.files[file], metadata.bytes == bytes.count,
                          SHA256.hash(data:bytes).map({String(format:"%02x",$0)}).joined() == metadata.sha256 else { throw CocoaError(.fileReadCorruptFile) }
                    return bytes
                }
                let meshData = try checked(manifest.mesh)
                guard meshData.count == manifest.vertices*64+manifest.indices*4,
                      let mesh = meshData.withUnsafeBytes({ device.makeBuffer(bytes:$0.baseAddress!,length:$0.count) }) else { throw CocoaError(.fileReadCorruptFile) }
                var clips: [String:[Float]] = [:]
                for (key,clip) in manifest.clips {
                    let bytes = try checked(clip.file)
                    guard clip.frames > 0, clip.duration > 0, bytes.count == clip.frames*manifest.bones.count*64 else { throw CocoaError(.fileReadCorruptFile) }
                    clips[key] = bytes.withUnsafeBytes { Array($0.bindMemory(to:Float.self)) }
                }
                resources[stage] = Resource(manifest:manifest,mesh:mesh,animations:clips)
            }
            lock.lock(); loadedStages = resources.count; lock.unlock()
            let library = try device.makeLibrary(source:Self.shader,options:nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name:"pack_vertex"); descriptor.fragmentFunction = library.makeFunction(name:"pack_fragment")
            descriptor.colorAttachments[0].pixelFormat = MTLPixelFormat(rawValue:colorPixelFormat)!
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.depthAttachmentPixelFormat = MTLPixelFormat(rawValue:depthStencilPixelFormat)!
            descriptor.stencilAttachmentPixelFormat = MTLPixelFormat(rawValue:depthStencilPixelFormat)!
            pipeline = try device.makeRenderPipelineState(descriptor:descriptor)
            let d = MTLDepthStencilDescriptor(); d.depthCompareFunction = .lessEqual; d.isDepthWriteEnabled = true
            depth = device.makeDepthStencilState(descriptor:d)
            for _ in 0..<3 {
                guard let instances = device.makeBuffer(length:MemoryLayout<Instance>.stride*16,options:.storageModeShared),
                      let bones = device.makeBuffer(length:64*64*16,options:.storageModeShared) else { throw CocoaError(.fileReadTooLarge) }
                buffers.append(FrameBuffers(instances:instances,bones:bones))
            }
        } catch { lock.lock(); failure = "Draft assets or GPU resources unavailable"; lock.unlock() }
    }
    func render(_ parameters: CustomLayerRenderParameters, mtlCommandBuffer: MTLCommandBuffer, mtlRenderPassDescriptor: MTLRenderPassDescriptor) {
        let start = CACurrentMediaTime()
        lock.lock()
        let characters = poses.sorted { $0.stage.rawValue < $1.stage.rawValue }
        guard enabled, !characters.isEmpty, let slot = freeSlots.popLast() else { lock.unlock(); return }
        lock.unlock()
        var submitted = false
        defer { if !submitted { lock.lock(); freeSlots.append(slot); lock.unlock() } }
        guard buffers.count == 3, let pipeline, let depth,
              let texture = mtlRenderPassDescriptor.colorAttachments[0].texture else { return }
        let frame = buffers[slot]
        let instances = frame.instances.contents().bindMemory(to:Instance.self,capacity:16)
        let boneData = frame.bones.contents().bindMemory(to:Float.self,capacity:16*64*16)
        let values = parameters.projectionMatrix.map(\.doubleValue)
        guard values.count == 16 else { return }
        var projection = matrix_identity_double4x4
        for c in 0..<4 { for r in 0..<4 { projection[c][r] = values[c*4+r] } }
        for (i,pose) in characters.enumerated() {
            guard let resource = resources[pose.stage], let clip = resource.manifest.clips[pose.clip], let samples = resource.animations[pose.clip] else { return }
            let seed = pose.id.uuidString.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
            var time = pose.animated ? start-epoch+Double(seed % 2400)/100 : 0
            if pose.detail == .simplified { time = floor(time*8)/8 }
            let progress = time.truncatingRemainder(dividingBy:clip.duration)/clip.duration*Double(clip.frames)
            let first = Int(progress)%clip.frames, second = (first+1)%clip.frames, blend = Float(progress-Double(first))
            let stride = resource.manifest.bones.count*16
            for j in 0..<stride { boneData[i*64*16+j] = samples[first*stride+j]*(1-blend)+samples[second*stride+j]*blend }
            let origin = CLLocationCoordinate2D(latitude:pose.latitude,longitude:pose.longitude)
            let projected = Projection.project(origin,zoomScale:CGFloat(pow(2,parameters.zoom)))
            let naturalScale = 1/Projection.metersPerPoint(for:origin.latitude,zoom:CGFloat(parameters.zoom))
            let scale = max(naturalScale, 24)
            let angle = (180-pose.heading)*Double.pi/180
            var model = matrix_identity_double4x4
            model[0][0] = cos(angle)*scale; model[0][1] = -sin(angle)*scale
            model[1][0] = -sin(angle)*scale; model[1][1] = -cos(angle)*scale
            model[2][2] = scale/naturalScale
            model[3][0] = projected.x; model[3][1] = projected.y
            model[3][2] = parameters.elevationData?.getElevationFor(origin)?.doubleValue ?? 0
            let matrix = projection*model
            var mvp = matrix_identity_float4x4
            for c in 0..<4 { for r in 0..<4 { mvp[c][r] = Float(matrix[c][r]) } }
            instances[i] = Instance(mvp:mvp,headingOpacity:SIMD4(Float(angle),Float(pose.opacity),0,0))
        }
        guard let encoder = mtlCommandBuffer.makeRenderCommandEncoder(descriptor:mtlRenderPassDescriptor) else { return }
        encoder.label = "Wolfy Pack: shared stage instances"
        encoder.setViewport(MTLViewport(originX:0,originY:0,width:Double(texture.width),height:Double(texture.height),znear:0,zfar:1))
        encoder.setRenderPipelineState(pipeline); encoder.setDepthStencilState(depth); encoder.setCullMode(.none)
        encoder.setVertexBuffer(frame.instances,offset:0,index:1); encoder.setVertexBuffer(frame.bones,offset:0,index:2)
        var first = 0
        while first < characters.count {
            let stage = characters[first].stage
            var end = first+1
            while end < characters.count && characters[end].stage == stage { end += 1 }
            if let resource = resources[stage] {
                encoder.setVertexBuffer(resource.mesh,offset:0,index:0)
                encoder.drawIndexedPrimitives(type:.triangle,indexCount:resource.manifest.indices,indexType:.uint32,
                    indexBuffer:resource.mesh,indexBufferOffset:resource.manifest.vertices*64,instanceCount:end-first,baseVertex:0,baseInstance:first)
            }
            first = end
        }
        encoder.endEncoding(); submitted = true
        mtlCommandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }; self.lock.lock(); self.freeSlots.append(slot); self.lock.unlock()
        }
        lock.lock(); submittedFrames += 1; cpuTimes.append((CACurrentMediaTime()-start)*1000)
        if cpuTimes.count > 600 { cpuTimes.removeFirst() }; lock.unlock()
    }
    func renderingWillEnd() { resources.removeAll(); buffers.removeAll(); pipeline = nil; depth = nil; lock.lock(); loadedStages = 0; lock.unlock() }
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position; float4 normal; float4 color; float4 joint; };
    struct Instance { float4x4 mvp; float4 headingOpacity; };
    struct Raster { float4 position [[position]]; float3 normal; float4 color; };
    vertex Raster pack_vertex(uint v [[vertex_id]], uint i [[instance_id]], device const Vertex* vertices [[buffer(0)]],
      device const Instance* instances [[buffer(1)]], device const float4x4* bones [[buffer(2)]]) {
      Vertex p = vertices[v]; Instance instance = instances[i];
      float4x4 skin = bones[i*64+uint(p.joint.x)]*(1.0-p.joint.z) + bones[i*64+uint(p.joint.y)]*p.joint.z;
      Raster out; out.position = instance.mvp*skin*p.position;
      float3 n = (skin*p.normal).xyz; float a = instance.headingOpacity.x;
      out.normal = normalize(float3(n.x*cos(a)-n.y*sin(a),n.x*sin(a)+n.y*cos(a),n.z));
      out.color = float4(p.color.rgb,instance.headingOpacity.y); return out;
    }
    fragment float4 pack_fragment(Raster in [[stage_in]]) {
      float light = .40+.60*max(0.0,dot(normalize(in.normal),normalize(float3(-.5,-.6,1))));
      return float4(in.color.rgb*light,in.color.a);
    }
    """
}
#endif
