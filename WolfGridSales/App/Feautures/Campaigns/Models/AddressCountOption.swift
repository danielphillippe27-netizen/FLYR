import Foundation

public enum AddressCountOption: Int, CaseIterable, Identifiable {
  case c25 = 25
  case c50 = 50
  case c100 = 100
  case c250 = 250
  case c500 = 500
  case c750 = 750
  case c1000 = 1000
  case c1500 = 1500
  case c2000 = 2000
  case c2500 = 2500
  
  public var id: Int { rawValue }
  
  public var label: String { "\(rawValue)" }
}

extension AddressCountOption: CustomStringConvertible {
  public var description: String { label }
}
