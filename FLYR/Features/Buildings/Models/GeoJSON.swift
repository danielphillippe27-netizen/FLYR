import Foundation

// MARK: - GeoJSON Models for Building Polygons

/// GeoJSON FeatureCollection containing building polygons
struct GeoJSONFeatureCollection: Codable, Equatable {
    let type: String // "FeatureCollection"
    var features: [GeoJSONFeature]
    
    init(features: [GeoJSONFeature] = []) {
        self.type = "FeatureCollection"
        self.features = features
    }
}

/// GeoJSON Feature containing a building polygon
struct GeoJSONFeature: Codable, Equatable {
    let type: String // "Feature"
    let id: String?
    let geometry: GeoJSONGeometry
    let properties: [String: AnyCodable]
    
    // Custom decoder to handle both string and number IDs (MVT tiles can have numeric IDs)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        geometry = try container.decode(GeoJSONGeometry.self, forKey: .geometry)
        properties = try container.decode([String: AnyCodable].self, forKey: .properties)
        
        // Handle id as either string or number (convert number to string)
        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let numberId = try? container.decode(Int.self, forKey: .id) {
            id = String(numberId)
        } else if let doubleId = try? container.decode(Double.self, forKey: .id), doubleId.isFinite {
            id = String(Int(doubleId))
        } else {
            id = nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, id, geometry, properties
    }
    
    init(id: String? = nil, geometry: GeoJSONGeometry, properties: [String: AnyCodable] = [:]) {
        self.type = "Feature"
        self.id = id
        self.geometry = geometry
        self.properties = properties
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(properties, forKey: .properties)
    }
}

/// GeoJSON Geometry (Polygon, MultiPolygon, etc.)
struct GeoJSONGeometry: Codable, Equatable {
    let type: String // "Polygon", "MultiPolygon", etc.
    let coordinates: AnyCodable // Flexible for different geometry types
    
    // Custom decoder to handle nested coordinate arrays
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        
        // Decode coordinates based on geometry type
        // Polygon: [[[Double]]] - array of rings, each ring is array of [lon, lat] pairs
        // MultiPolygon: [[[[Double]]]] - array of polygons
        var coordinatesContainer = try container.nestedUnkeyedContainer(forKey: .coordinates)
        
        if type == "Polygon" {
            // Polygon: [[[Double]]] - outer array of rings
            var polygonArray: [[[Double]]] = []
            while !coordinatesContainer.isAtEnd {
                // Each ring is an array of coordinates
                var ringContainer = try coordinatesContainer.nestedUnkeyedContainer()
                var ring: [[Double]] = []
                while !ringContainer.isAtEnd {
                    // Each coordinate is [lon, lat] - array of 2 doubles
                    var coordContainer = try ringContainer.nestedUnkeyedContainer()
                    var coord: [Double] = []
                    while !coordContainer.isAtEnd {
                        coord.append(try coordContainer.decode(Double.self))
                    }
                    ring.append(coord)
                }
                polygonArray.append(ring)
            }
            coordinates = AnyCodable(polygonArray)
        } else if type == "MultiPolygon" {
            // MultiPolygon: [[[[Double]]]] - array of polygons
            var multiPolygonArray: [[[[Double]]]] = []
            while !coordinatesContainer.isAtEnd {
                // Each polygon is an array of rings
                var polygonContainer = try coordinatesContainer.nestedUnkeyedContainer()
                var polygon: [[[Double]]] = []
                while !polygonContainer.isAtEnd {
                    // Each ring is an array of coordinates
                    var ringContainer = try polygonContainer.nestedUnkeyedContainer()
                    var ring: [[Double]] = []
                    while !ringContainer.isAtEnd {
                        // Each coordinate is [lon, lat]
                        var coordContainer = try ringContainer.nestedUnkeyedContainer()
                        var coord: [Double] = []
                        while !coordContainer.isAtEnd {
                            coord.append(try coordContainer.decode(Double.self))
                        }
                        ring.append(coord)
                    }
                    polygon.append(ring)
                }
                multiPolygonArray.append(polygon)
            }
            coordinates = AnyCodable(multiPolygonArray)
        } else {
            // For other types, throw error (we only support Polygon and MultiPolygon for buildings)
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported geometry type for coordinate decoding: \(type). Only Polygon and MultiPolygon are supported."
                )
            )
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, coordinates
    }
    
    init(type: String, coordinates: AnyCodable) {
        self.type = type
        self.coordinates = coordinates
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        
        // Encode coordinates based on type
        // Note: We manually encode nested arrays since AnyCodable can't encode arrays
        if type == "Polygon", let polygonCoords = coordinates.value as? [[[Double]]] {
            var coordinatesContainer = container.nestedUnkeyedContainer(forKey: .coordinates)
            for ring in polygonCoords {
                var ringContainer = coordinatesContainer.nestedUnkeyedContainer()
                for coord in ring {
                    try ringContainer.encode(coord) // [Double] can be encoded directly
                }
            }
        } else if type == "MultiPolygon", let multiPolygonCoords = coordinates.value as? [[[[Double]]]] {
            var coordinatesContainer = container.nestedUnkeyedContainer(forKey: .coordinates)
            for polygon in multiPolygonCoords {
                var polygonContainer = coordinatesContainer.nestedUnkeyedContainer()
                for ring in polygon {
                    var ringContainer = polygonContainer.nestedUnkeyedContainer()
                    for coord in ring {
                        try ringContainer.encode(coord) // [Double] can be encoded directly
                    }
                }
            }
        } else {
            // For unsupported types, we can't encode (but this shouldn't happen for buildings)
            throw EncodingError.invalidValue(
                coordinates,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Cannot encode coordinates for type: \(type)"
                )
            )
        }
    }
}

// MARK: - AnyCodable Helper
// Using AnyCodable from SupabaseClientShim.swift
