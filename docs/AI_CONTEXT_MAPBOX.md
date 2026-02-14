# FLYR Mapbox Integration

Reference for Mapbox Maps SDK integration, sources, layers, styles, and rendering patterns.

## Mapbox Setup

### Initialization

**MapboxManager.swift** initializes Mapbox with access token from `Info.plist`:

```swift
MapboxMapsOptions.accessToken = Bundle.main.object(
  forInfoDictionaryKey: "MAPBOX_ACCESS_TOKEN"
) as! String
```

### MapView Integration

**UIViewRepresentable** wrapper for `MapboxMapView`:
- `SessionMapboxViewRepresentable` - Session recording map
- `MapboxViewContainer` - Generic map container

---

## Map Styles & Themes

### MapTheme Enum

**Light Theme**:
- Style URL: `mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4`
- Use for: Daytime, default view

**Dark Theme**:
- Style URL: `mapbox://styles/fliper27/cml6zc5pq002801qo4lh13o19`
- Use for: Night mode, dark UI

**Custom JSON Styles** (legacy, in bundle):
- `LightStyle.json`
- `DarkStyle.json`
- `BlackWhite3DStyle.json`
- `Campaign3DStyle.json`

### Switching Styles

```swift
mapView.mapboxMap.loadStyle(theme.styleURL)
```

---

## Sources & Layers

### Source IDs

**Buildings Source**:
- ID: `buildingsSource`
- Type: GeoJSON
- Data: FeatureCollection from `rpc_get_campaign_full_features`
- Geometry: Polygon, MultiPolygon
- Properties: `status`, `height`, `formatted`, `scans_total`, `gers_id`

**Roads Source**:
- ID: `roadsSource`
- Type: GeoJSON
- Data: FeatureCollection from `rpc_get_campaign_roads`
- Geometry: LineString
- Properties: `name`, `road_class`

**Addresses Source**:
- ID: `addressesSource`
- Type: GeoJSON
- Data: FeatureCollection from `rpc_get_campaign_addresses`
- Geometry: Point
- Properties: `formatted`, `postal_code`, `city`, `gers_id`

---

### Layer IDs & Types

**Buildings Layer**:
- ID: `buildingsExtrusionLayer`
- Type: `fill-extrusion` (3D buildings)
- Source: `buildingsSource`
- **CRITICAL FILTER**: Must filter to polygon geometry only!

```swift
layer.filter = Exp(.inExpression) {
  Exp(.geometryType)
  ["Polygon", "MultiPolygon"]
}
```

**Why filter is required**:
- Prevents "Expected Polygon/MultiPolygon but got LineString" errors
- GeoJSON may inadvertently include non-polygon features
- Mapbox fill-extrusion crashes without filter

**Roads Layer**:
- ID: `roadsLineLayer`
- Type: `line`
- Source: `roadsSource`
- Style: Line width, color, opacity

**Addresses Layer**:
- ID: `addressesCircleLayer`
- Type: `circle`
- Source: `addressesSource`
- Style: Circle radius, color, stroke

---

## 3D Building Extrusion

### Height Property

Buildings are extruded based on `height` or `height_m` property:

```swift
layer.fillExtrusionHeight = .expression(
  Exp(.get) { "height_m" }
)
```

**Height Sources**:
- Mapbox Vector Tiles: `height` property (in meters)
- Custom data: `height_m` property (explicit meters)
- Fallback: 10 meters if missing

### Base Height

Optional base height for buildings on slopes:

```swift
layer.fillExtrusionBase = .constant(0)
```

---

## Status-Based Colors

### Color Logic

Buildings change color based on visit status and scan count:

**Yellow** - QR Scanned:
- Condition: `scans_total > 0`
- RGB: `#FFD700` (gold)

**Blue** - Conversation:
- Condition: `status = 'talked'`
- RGB: `#4A90E2` (blue)

**Green** - Touched (delivered or no answer):
- Condition: `status IN ('delivered', 'no_answer')`
- RGB: `#7ED321` (green)

**Red** - Untouched:
- Condition: `status = 'none'` OR `status IS NULL`
- RGB: `#D0021B` (red)

**Gray** - Do Not Knock:
- Condition: `status = 'do_not_knock'`
- RGB: `#9B9B9B` (gray)

### Expression Implementation

```swift
layer.fillExtrusionColor = .expression(
  Exp(.switchCase) {
    // QR Scanned (yellow)
    Exp(.gt) {
      Exp(.get) { "scans_total" }
      0
    }
    UIColor.yellow
    
    // Talked (blue)
    Exp(.eq) {
      Exp(.get) { "status" }
      "talked"
    }
    UIColor.blue
    
    // Delivered/No Answer (green)
    Exp(.inExpression) {
      Exp(.get) { "status" }
      ["delivered", "no_answer"]
    }
    UIColor.green
    
    // Default: Untouched (red)
    UIColor.red
  }
)
```

---

## Real-Time Updates

### Feature State (Instant Updates)

Use feature state for instant color changes without reloading source:

```swift
try mapView.mapboxMap.setFeatureState(
  sourceId: "buildingsSource",
  sourceLayerId: nil,
  featureId: addressId.uuidString,
  state: ["status": "delivered", "scans_total": 0]
)
```

**Advantages**:
- No network request
- No GeoJSON re-parse
- Instant visual feedback
- Preserves other feature properties

### Source Update (Full Reload)

Reload entire source when adding/removing features:

```swift
var source = GeoJSONSource(id: "buildingsSource")
source.data = .featureCollection(newFeatureCollection)
try mapView.mapboxMap.updateGeoJSONSource(
  withId: "buildingsSource",
  geoJSON: source.data!
)
```

**Use when**:
- Adding new buildings
- Removing buildings
- Changing geometries
- Large batch updates

---

## 3D Lighting

### Ambient Light

Global ambient light for scene:

```swift
mapView.mapboxMap.style.ambientLight = AmbientLight()
ambientLight.color = .constant(StyleColor(.white))
ambientLight.intensity = .constant(0.5)
```

### Directional Light

Simulates sun position:

```swift
mapView.mapboxMap.style.directionalLight = DirectionalLight()
directionalLight.direction = .constant([0, 45]) // [azimuth, polar]
directionalLight.intensity = .constant(0.8)
```

**Best settings for buildings**:
- Azimuth: 315° (northwest)
- Polar: 45° (45° above horizon)
- Intensity: 0.6-0.8

---

## Camera & Viewport

### Camera Position

```swift
let camera = CameraOptions(
  center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
  zoom: 16, // Building detail level
  bearing: 0, // North up
  pitch: 60 // 3D tilt angle
)
mapView.camera.fly(to: camera, duration: 1.0)
```

**Zoom Levels**:
- 12-14: Neighborhood overview (roads visible)
- 15-16: Street level (buildings + addresses)
- 17-18: Building detail (individual units)
- 19+: Extreme close-up (not recommended for 3D)

**Pitch Angles**:
- 0°: 2D top-down view
- 30-45°: Slight 3D tilt
- 60°: Full 3D perspective (recommended for buildings)
- 85°: Maximum tilt

---

## Bounding Box Queries

### Viewport-Based Loading

Load only visible features for performance:

```swift
let bounds = mapView.mapboxMap.coordinateBounds(for: mapView.bounds)
let bbox = [
  bounds.southwest.longitude,
  bounds.southwest.latitude,
  bounds.northeast.longitude,
  bounds.northeast.latitude
]

let features = try await supabase.rpc(
  "rpc_get_buildings_in_bbox",
  params: [
    "min_lon": bbox[0],
    "min_lat": bbox[1],
    "max_lon": bbox[2],
    "max_lat": bbox[3],
    "p_campaign_id": campaignId
  ]
)
```

**Use when**:
- Large campaigns (>1000 buildings)
- Zoomed in views
- Panning/scrolling
- Performance optimization

---

## Gesture Handling

### Tap Gestures

Detect tapped features:

```swift
mapView.gestures.onMapTap.observe { [weak self] context in
  let screenPoint = context.point
  
  let features = try? mapView.mapboxMap.queryRenderedFeatures(
    with: screenPoint,
    options: RenderedQueryOptions(
      layerIds: ["buildingsExtrusionLayer"],
      filter: nil
    )
  )
  
  if let feature = features?.first {
    // Handle building tap
    let addressId = feature.identifier
    let status = feature.properties["status"]
  }
}
```

### Long Press Gestures

```swift
let longPress = UILongPressGestureRecognizer(
  target: self,
  action: #selector(handleLongPress)
)
mapView.addGestureRecognizer(longPress)
```

---

## Performance Optimization

### Clustering (Addresses)

Enable clustering for many address markers:

```swift
var source = GeoJSONSource(id: "addressesSource")
source.cluster = true
source.clusterRadius = 50
source.clusterMaxZoom = 14
```

### Layer Visibility

Hide/show layers based on zoom:

```swift
layer.minZoom = 15 // Only show at zoom 15+
layer.maxZoom = 20 // Hide after zoom 20
```

### Simplification

Simplify geometries for distant views:

```swift
layer.fillExtrusionOpacity = .expression(
  Exp(.interpolate) {
    Exp(.linear)
    Exp(.zoom)
    12
    0.0 // Transparent at low zoom
    15
    1.0 // Opaque at high zoom
  }
)
```

---

## Common Issues & Solutions

### Issue 1: "Expected Polygon but got LineString"

**Problem**: Fill-extrusion layer receives LineString geometries
**Solution**: Add geometry type filter:

```swift
layer.filter = Exp(.inExpression) {
  Exp(.geometryType)
  ["Polygon", "MultiPolygon"]
}
```

### Issue 2: Buildings not rendering

**Checklist**:
1. Source has valid GeoJSON FeatureCollection
2. Features have Polygon/MultiPolygon geometries
3. Layer references correct source ID
4. Layer is added to map
5. Camera is positioned correctly (zoom 15+, pitch 60)
6. Height property exists and is > 0

### Issue 3: Colors not updating

**Solutions**:
- Use feature state for instant updates
- Verify feature ID matches (UUID string format)
- Check expression logic matches status values

### Issue 4: Map performance degradation

**Solutions**:
- Use bounding box queries (viewport-based loading)
- Enable clustering for addresses
- Simplify geometries at low zoom
- Limit feature count (<5000 per source)

---

## Testing & Debugging

### Print Source Data

```swift
if let source = try? mapView.mapboxMap.source(withId: "buildingsSource") as? GeoJSONSource {
  print("Buildings source:", source.data)
}
```

### Query Features

```swift
let allFeatures = try? mapView.mapboxMap.querySourceFeatures(
  for: "buildingsSource",
  options: SourceQueryOptions(sourceLayerIds: nil, filter: nil)
)
print("Total buildings:", allFeatures?.count)
```

### Inspect Feature Properties

```swift
if let feature = features.first,
   case let .object(properties) = feature.properties {
  print("Status:", properties["status"])
  print("Height:", properties["height_m"])
}
```

---

## Best Practices

1. **Always filter fill-extrusion layers** to polygon geometries
2. **Use feature state** for real-time status updates
3. **Use bounding box queries** for large datasets
4. **Set pitch to 60°** for optimal 3D building view
5. **Cache GeoJSON** in memory to avoid re-fetching
6. **Handle empty FeatureCollections** gracefully
7. **Test with 1000+ buildings** for performance validation
8. **Use directional lighting** for realistic 3D appearance
