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
}







