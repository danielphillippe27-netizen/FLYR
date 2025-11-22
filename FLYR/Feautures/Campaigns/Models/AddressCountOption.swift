import Foundation

public enum AddressCountOption: Int, CaseIterable, Identifiable {
  case c25 = 25, c50 = 50, c100 = 100, c250 = 250, c500 = 500, c750 = 750, c1000 = 1000
  
  public var id: Int { rawValue }
  
  public var label: String { "\(rawValue)" }
}

extension AddressCountOption: CustomStringConvertible {
  public var description: String { label }
}