import Foundation
import CoreLocation

extension GeoAPI {
  func reverseAddressString(at coordinate: CLLocationCoordinate2D) async throws -> String {
    guard !token.isEmpty else { throw GeoAPIError.missingToken }
    // Mapbox requires limit to be combined with a single type for reverse geocoding
    let urlStr = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(coordinate.longitude),\(coordinate.latitude).json?types=address&limit=1&access_token=\(token)"
    guard let url = URL(string: urlStr) else { throw GeoAPIError.badURL }
    let (data, resp) = try await URLSession.shared.data(from: url)
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw GeoAPIError.requestFailed }
    struct Resp: Decodable { struct F: Decodable { let place_name: String }; let features: [F] }
    let r = try JSONDecoder().decode(Resp.self, from: data)
    return r.features.first?.place_name ?? "Dropped Pin"
  }

  func reverseProvisionRegionCode(at coordinate: CLLocationCoordinate2D) async throws -> String {
    guard !token.isEmpty else { throw GeoAPIError.missingToken }
    let urlStr = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(coordinate.longitude),\(coordinate.latitude).json?types=region,country&country=ca,us,nz,au,za,gb&access_token=\(token)"
    guard let url = URL(string: urlStr) else { throw GeoAPIError.badURL }
    let (data, resp) = try await URLSession.shared.data(from: url)
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw GeoAPIError.requestFailed }

    struct Resp: Decodable {
      struct Context: Decodable {
        let short_code: String?
        let text: String?
      }

      struct Feature: Decodable {
        let short_code: String?
        let text: String?
        let context: [Context]?
      }

      let features: [Feature]
    }

    func normalize(_ value: String?) -> String? {
      guard let value else { return nil }
      let upper = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      if upper.count == 2 { return upper }
      let pieces = upper.split(separator: "-")
      if pieces.count == 2, pieces[1].count == 2 {
        return String(pieces[1])
      }
      switch upper {
      case "CANADA": return "CA"
      case "UNITED STATES", "UNITED STATES OF AMERICA": return "US"
      case "NEW ZEALAND": return "NZ"
      case "AUSTRALIA": return "AU"
      case "SOUTH AFRICA": return "ZA"
      case "UNITED KINGDOM", "GREAT BRITAIN": return "GB"
      default: return nil
      }
    }

    let decoded = try JSONDecoder().decode(Resp.self, from: data)
    var candidates: [String] = []
    for feature in decoded.features {
      if let code = normalize(feature.short_code) ?? normalize(feature.text) {
        candidates.append(code)
      }
      for context in feature.context ?? [] {
        if let code = normalize(context.short_code) ?? normalize(context.text) {
          candidates.append(code)
        }
      }
    }

    if let southAfricaProvince = candidates.first(where: { ["EC", "FS", "GP", "KZN", "LP", "MP", "NC", "NW", "WC"].contains($0) }) {
      return southAfricaProvince
    }

    if let region = candidates.first(where: { !["CA", "US"].contains($0) }) {
      return region
    }

    if let country = candidates.first(where: { ["NZ", "AU", "ZA", "GB"].contains($0) }) {
      return country
    }

    throw GeoAPIError.noResults
  }
}






