import Foundation
import CoreLocation
import Combine

@MainActor
final class UseAddressAutocomplete: ObservableObject {
  @Published var query: String = ""
  @Published var suggestions: [AddressSuggestion] = []
  @Published var isLoading: Bool = false
  @Published var error: String?
  @Published var selected: AddressSuggestion?

  private var debounceTask: Task<Void, Never>?
  private var currentRequestID: UInt64 = 0   // ← identify latest request

  func bind() {
    debounceTask?.cancel()
    debounceTask = Task { [weak self] in
      guard let self else { return }
      for await text in self.$query.values {
        await self.search(text: text)
      }
    }
  }

  func clear() {
    debounceTask?.cancel()
    isLoading = false
    suggestions.removeAll()
  }

  func search(text: String, proximity: CLLocationCoordinate2D? = nil) async {
    error = nil
    guard text.trimmingCharacters(in: .whitespaces).count >= 3 else {
      suggestions.removeAll()
      return
    }
    isLoading = true
    let req = currentRequestID &+ 1
    currentRequestID = req
    do {
      let results = try await GeoAPI.shared.autocomplete(text, proximity: proximity)
      // Ignore late/outdated responses
      guard req == currentRequestID else { return }
      suggestions = results
    } catch {
      guard req == currentRequestID else { return }
      self.error = "\(error)"
      suggestions.removeAll()
    }
    isLoading = false
  }

  func pick(_ s: AddressSuggestion) {
    // Fill, select, and collapse dropdown
    selected = s
    query = formatted(s)
    currentRequestID &+= 1         // invalidate any in-flight responses
    clear()
  }

  private func formatted(_ s: AddressSuggestion) -> String {
    if let sub = s.subtitle, !sub.isEmpty { return "\(s.title), \(sub)" }
    return s.title
  }
}
