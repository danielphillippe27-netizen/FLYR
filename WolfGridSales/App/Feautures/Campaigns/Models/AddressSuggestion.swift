import Foundation
import CoreLocation

public struct AddressSuggestion: Identifiable, Hashable {
  public let id: String          // mapbox feature id
  public let title: String       // main line
  public let subtitle: String?   // city/postal
  public let coordinate: CLLocationCoordinate2D
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(title)
    hasher.combine(subtitle)
    hasher.combine(coordinate.latitude)
    hasher.combine(coordinate.longitude)
  }
  
  public static func == (lhs: AddressSuggestion, rhs: AddressSuggestion) -> Bool {
    return lhs.id == rhs.id &&
           lhs.title == rhs.title &&
           lhs.subtitle == rhs.subtitle &&
           lhs.coordinate.latitude == rhs.coordinate.latitude &&
           lhs.coordinate.longitude == rhs.coordinate.longitude
  }
}
