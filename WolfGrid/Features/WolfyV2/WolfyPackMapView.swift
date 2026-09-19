#if DEBUG
import SwiftUI
import MapboxMaps
import Turf

struct WolfyPackMapViewV2: UIViewRepresentable {
    let inputs: [WolfyPackMotionV2.Input]
    let local: UUID?
    let selected: UUID?
    let active: Bool
    let reduceMotion: Bool
    var serverOffset: TimeInterval = 0
    var syntheticCapture = false
    var onSelect: (UUID) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MapView {
        let fix = inputs.compactMap(\.fix).first
        let center = CLLocationCoordinate2D(latitude:fix?.latitude ?? 43.65324,longitude:fix?.longitude ?? -79.3837)
        let map = DisplayLinkRecoveringMapView(frame:.zero,mapInitOptions:MapInitOptions(
            cameraOptions:CameraOptions(center:center,zoom:20.5,bearing:0,pitch:55),styleURI:.streets))
        context.coordinator.install(map,capture:syntheticCapture)
        return map
    }
    func updateUIView(_ map: MapView, context: Context) {
        let c = context.coordinator
        c.local = local; c.selected = selected; c.reduceMotion = reduceMotion; c.serverOffset = serverOffset; c.onSelect = onSelect
        c.motion.replace(inputs,now:Date().addingTimeInterval(serverOffset))
        c.setActive(active)
    }
    static func dismantleUIView(_ map: MapView, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var map: MapView?
        let renderer = WolfyPackRendererV2()
        var motion = WolfyPackMotionV2()
        var local: UUID?, selected: UUID?
        var reduceMotion = false
        var serverOffset: TimeInterval = 0
        var onSelect: (UUID)->Void = { _ in }
        private var link: CADisplayLink?
        private var loaded: AnyCancelable?
        private var captureTasks: [DispatchWorkItem] = []
        private var latest: [WolfyPackMotionV2.Pose] = []
        private var groupHits: [(point: CGPoint, center: CLLocationCoordinate2D)] = []
        private var labelTime = Date.distantPast
        private let sourceID = "wolfy-pack-points"
        private var installed = false
        func install(_ map: MapView,capture: Bool) {
            self.map = map
            let tap = UITapGestureRecognizer(target:self,action:#selector(tap(_:)))
            tap.cancelsTouchesInView = false; tap.delegate = self; map.addGestureRecognizer(tap)
            loaded = map.mapboxMap.onStyleLoaded.observe { [weak self] _ in
                guard let self, let map = self.map else { return }
                do {
                    var source = GeoJSONSource(id:self.sourceID); source.data = .featureCollection(FeatureCollection(features:[]))
                    try map.mapboxMap.addSource(source)
                    try map.mapboxMap.addCustomLayer(withId:"wolfy-pack-meshes",layerHost:self.renderer,layerPosition:nil)
                    if let image = UIImage(systemName:"pawprint.fill") { try map.mapboxMap.addImage(image,id:"wolfy-pack-marker") }
                    var markers = SymbolLayer(id:"wolfy-pack-markers",source:self.sourceID)
                    markers.filter = Exp(.eq) { Exp(.get) { "detail" }; 2 }
                    markers.iconImage = .constant(.name("wolfy-pack-marker")); markers.iconSize = .constant(0.7)
                    markers.iconOpacity = .expression(Exp(.get) { "opacity" })
                    markers.iconAllowOverlap = .constant(true)
                    try map.mapboxMap.addLayer(markers)
                    var labels = SymbolLayer(id:"wolfy-pack-names",source:self.sourceID)
                    labels.textField = .expression(Exp(.get) { "name" }); labels.textSize = .constant(11)
                    labels.textColor = .constant(StyleColor(.white)); labels.textHaloColor = .constant(StyleColor(.black)); labels.textHaloWidth = .constant(1)
                    labels.textOffset = .constant([0,1.8]); labels.textAllowOverlap = .constant(false); labels.textIgnorePlacement = .constant(false)
                    labels.textOpacity = .expression(Exp(.interpolate) {
                        Exp(.linear); Exp(.zoom)
                        18; Exp(.switchCase) {
                            Exp(.eq) { Exp(.get) { "detail" }; 2 }; Exp(.get) { "opacity" }; 0
                        }
                        20; Exp(.get) { "opacity" }
                    })
                    try map.mapboxMap.addLayer(labels)
                    var you = CircleLayer(id:"wolfy-pack-you",source:self.sourceID)
                    you.filter = Exp(.eq) { Exp(.get) { "you" }; true }
                    you.circleRadius = .constant(9); you.circleColor = .constant(StyleColor(.systemYellow)); you.circleOpacity = .constant(0.22)
                    try map.mapboxMap.addLayer(you,layerPosition:.below("wolfy-pack-meshes"))
                    self.installed = true
                } catch { print("Wolfy Pack development map could not install: \(error)") }
                if capture {
                    for (index,delay) in [8.0,9.0].enumerated() {
                        let task = DispatchWorkItem { [weak self] in
                            guard let self, let map = self.map else { return }
                            let directory = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
                            do {
                                try map.snapshot(includeOverlays:true).pngData()?.write(to:directory.appendingPathComponent("wolfy-pack-prototype-\(index).png"))
                                let report = "\(self.renderer.diagnostic), visible=\(self.latest.count), full=\(self.latest.filter{$0.detail == .full}.count), simplified=\(self.latest.filter{$0.detail == .simplified}.count)"
                                try report.write(to:directory.appendingPathComponent("wolfy-pack-prototype-\(index).txt"),atomically:true,encoding:.utf8)
                            } catch { print("Pack synthetic capture failed: \(error)") }
                        }
                        self.captureTasks.append(task); DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:task)
                    }
                }
            }
        }
        func setActive(_ active: Bool) {
            if active, link == nil {
                let timer = CADisplayLink(target:self,selector:#selector(frame)); timer.preferredFramesPerSecond = 30
                timer.add(to:.main,forMode:.common); link = timer
            } else if !active {
                link?.invalidate(); link = nil; latest = []; groupHits = []; motion.clear(); renderer.update([],enabled:false)
                if installed { map?.mapboxMap.updateGeoJSONSource(withId:sourceID,geoJSON:.featureCollection(FeatureCollection(features:[]))) }
            }
        }
        @objc private func frame() {
            guard let map, installed else { return }
            let now = Date().addingTimeInterval(serverOffset), center = map.mapboxMap.cameraState.center
            let camera = WolfyPackFixV2(latitude:center.latitude,longitude:center.longitude,accuracy:0,heading:0,speed:0,fixedAt:now,sequence:0)
            let constrained = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
            let allPoses = motion.poses(now:now,center:camera,selected:selected,local:local,reduceMotion:reduceMotion,constrained:constrained) { latitude,longitude in
                map.bounds.insetBy(dx:-24,dy:-24).contains(map.mapboxMap.point(for:CLLocationCoordinate2D(latitude:latitude,longitude:longitude)))
            }
            let layout = WolfyPackLayoutV2(points: allPoses.map { pose in
                let p = map.mapboxMap.point(for: CLLocationCoordinate2D(latitude: pose.latitude, longitude: pose.longitude))
                return .init(id: pose.id, x: p.x, y: p.y)
            }, local: local, selected: selected, zoom: map.mapboxMap.cameraState.zoom, constrained: constrained)
            let byID = Dictionary(uniqueKeysWithValues: allPoses.map { ($0.id, $0) })
            latest = layout.individuals.enumerated().compactMap { index, id in
                guard let p = byID[id] else { return nil }
                return WolfyPackMotionV2.Pose(id:p.id,stage:p.stage,latitude:p.latitude,longitude:p.longitude,
                    heading:p.heading,clip:p.clip,opacity:p.opacity,detail:index < 6 ? .full : .simplified,
                    firstName:p.firstName,animated:p.animated)
            }
            groupHits = layout.groups.map { group in
                let members = group.members.compactMap { byID[$0] }
                return (CGPoint(x:group.x,y:group.y), CLLocationCoordinate2D(
                    latitude:members.map(\.latitude).reduce(0,+)/Double(members.count),
                    longitude:members.map(\.longitude).reduce(0,+)/Double(members.count)))
            }
            renderer.update(latest,enabled:true)
            if now.timeIntervalSince(labelTime)>=0.2 {
                labelTime = now
                var features = latest.map { pose -> Feature in
                    var f = Feature(geometry:.point(Point(CLLocationCoordinate2D(latitude:pose.latitude,longitude:pose.longitude))))
                    f.properties = ["name":.string(pose.id == local ? "YOU" : pose.firstName),"you":.boolean(pose.id == local),
                                    "detail":.number(Double(pose.detail.rawValue)),"opacity":.number(pose.opacity)]
                    return f
                }
                features += layout.groups.map { group in
                    let coordinate = map.mapboxMap.coordinate(for: CGPoint(x:group.x,y:group.y))
                    var f = Feature(geometry:.point(Point(coordinate)))
                    f.properties = ["name":.string("Pack × \(group.members.count)"),"you":.boolean(false),
                        "detail":.number(2),"opacity":.number(group.members.compactMap { byID[$0]?.opacity }.max() ?? 1)]
                    return f
                }
                map.mapboxMap.updateGeoJSONSource(withId:sourceID,geoJSON:.featureCollection(FeatureCollection(features:features)))
            }
            map.mapboxMap.triggerRepaint()
        }
        @objc private func tap(_ recognizer: UITapGestureRecognizer) {
            guard let map else { return }
            let point = recognizer.location(in:map)
            if let group = groupHits.first(where: { hypot($0.point.x-point.x,$0.point.y-point.y) < 36 }) {
                map.camera.ease(to: CameraOptions(center:group.center,zoom:min(22,map.mapboxMap.cameraState.zoom+2)),duration:0.45)
                return
            }
            let hits = latest.map { pose -> (UUID,CGFloat) in
                let projected = map.mapboxMap.point(for:CLLocationCoordinate2D(latitude:pose.latitude,longitude:pose.longitude))
                return (pose.id,hypot(projected.x-point.x,projected.y-point.y))
            }.filter { $0.1<=28 }.sorted { $0.1<$1.1 }
            if let hit = hits.first { onSelect(hit.0) }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        func stop() { setActive(false); loaded?.cancel(); captureTasks.forEach{$0.cancel()}; captureTasks.removeAll() }
        deinit { link?.invalidate() }
    }
}
struct WolfyPackPrototypeEntryView: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: UUID?
    @State private var ids = (0..<50).map { _ in UUID() }
    @State private var session = UUID()
    var body: some View {
        VStack {
            Text("Pack rendering · 50 simulated members").font(.headline)
            Text("Development art · synthetic locations").font(.caption)
            TimelineView(.periodic(from:.now,by:5)) { context in
                let inputs = ids.enumerated().map { i,id in
                    WolfyPackMotionV2.Input(id:id,stage:WolfyStage(rawValue:i%5+1)!,
                        fix:WolfyPackFixV2(latitude:43.65324+Double(i/5)*0.000014,longitude:-79.3837+Double(i%5)*0.000020,
                            accuracy:3,heading:Double(i%4)*90,speed:0,fixedAt:context.date,sequence:Int64(context.date.timeIntervalSince1970*1000)),
                        session:session,activity:.idle,firstName:"Rep \(i+1)")
                }
                WolfyPackMapViewV2(inputs:inputs,local:ids.first,selected:selected,active:phase == .active,
                                  reduceMotion:reduceMotion,syntheticCapture:true,onSelect:{ selected = $0 })
            }
            if let selected, let index = ids.firstIndex(of:selected) { Text("Selected Rep \(index+1) · \(WolfyStage(rawValue:index%5+1)!.title)").padding() }
        }
    }
}
#endif
