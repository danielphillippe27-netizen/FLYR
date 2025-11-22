import Foundation
import Combine

@MainActor
final class UseFarmCreate: ObservableObject {
  @Published var name = ""
  @Published var areaLabel = ""
  @Published var frequency: Int = 30
  @Published var includeFlyer = true
  @Published var includeDoorKnock = true
  @Published var includePopBy = false
  @Published var includeSurvey = false
  @Published var isSaving = false
  @Published var error: String?

  func create() async {
    isSaving = true; defer { isSaving = false }
    do {
      try await FarmAPI.shared.createFarm(
        name: name,
        areaLabel: areaLabel,
        frequencyDays: frequency,
        phases: [
          includeFlyer ? "flyer" : nil,
          includeDoorKnock ? "door_knock" : nil,
          includePopBy ? "pop_by" : nil,
          includeSurvey ? "survey" : nil
        ].compactMap { $0 }
      )
    } catch {
      self.error = "\(error)"
    }
  }
}
