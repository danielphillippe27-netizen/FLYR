import Foundation
import CoreLocation

extension GeoAPI {
  func autocomplete(_ query: String,
                    proximity: CLLocationCoordinate2D? = nil,
                    limit: Int = 8,
                    countries: [String] = ["US","CA"],
                    language: String = "en") async throws -> [AddressSuggestion] {
    guard !token.isEmpty else { throw GeoAPIError.missingToken }
    let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

    var urlStr = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(q).json"
    var parts: [String] = []
    parts += [
      "types=address",              // <- force address points (with numbers)
      "autocomplete=true",
      "fuzzyMatch=true",
      "limit=\(min(max(limit,1),10))",
      "language=\(language)"
    ]
    if !countries.isEmpty { parts.append("country=\(countries.joined(separator: ","))") }
    if let p = proximity { parts.append("proximity=\(p.longitude),\(p.latitude)") }
    parts.append("access_token=\(token)")
    urlStr += "?\(parts.joined(separator: "&"))"

    guard let url = URL(string: urlStr) else { throw GeoAPIError.badURL }
    let (data, resp) = try await URLSession.shared.data(from: url)
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw GeoAPIError.requestFailed }

    struct Resp: Decodable {
      struct Ctx: Decodable { let id: String; let text: String? }
      struct Feature: Decodable {
        let id: String
        let place_type: [String]
        let place_name: String      // full label (often includes number)
        let text: String            // street name
        let center: [Double]
        let context: [Ctx]?
        let address: String?        // <- top-level number
        let properties: Props?
        struct Props: Decodable { let address: String? } // <- sometimes here
      }
      let features: [Feature]
    }

    let decoded = try JSONDecoder().decode(Resp.self, from: data)

    return decoded.features.compactMap { f in
      guard f.center.count == 2 else { return nil }

      // Prefer explicit address number, then fallback to regex from place_name
      let explicitNumber = f.address ?? f.properties?.address
      let number = explicitNumber ?? f.place_name.firstLeadingNumber()

      // Title like "5900 Main Street" if we have a number, else fallback
      let title = [number, f.text].compactMap { $0 }.joined(separator: " ").trimmed()
      let fullTitle = title.isEmpty ? f.place_name : title

      // City + postcode subtitle
      let city = f.context?.first(where: { $0.id.hasPrefix("place") || $0.id.hasPrefix("locality") })?.text
      let postal = f.context?.first(where: { $0.id.hasPrefix("postcode") })?.text
      let subtitle = [city, postal].compactMap { $0 }.joined(separator: " ").nilIfEmpty

      return AddressSuggestion(
        id: f.id,
        title: fullTitle,
        subtitle: subtitle,
        coordinate: .init(latitude: f.center[1], longitude: f.center[0])
      )
    }
  }
}

private extension String {
  func firstLeadingNumber() -> String? {
    // grabs the first number at the start of the label: "5900 Main St…" -> "5900"
    let pattern = #"^\s*(\d+[A-Za-z]?)\b"#    // supports 12A, 5900B, etc.
    return range(of: pattern, options: .regularExpression).map { String(self[$0]).trimmed() }
  }
  func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
