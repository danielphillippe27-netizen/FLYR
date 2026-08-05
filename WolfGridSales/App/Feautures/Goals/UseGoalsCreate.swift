import Foundation
import Combine

@MainActor
final class UseGoalsCreate: ObservableObject {
  @Published var name = ""
  @Published var type = "flyers"
  @Published var target = 100
  @Published var dueDate = Date().addingTimeInterval(86400*30)
  @Published var isSaving = false
  @Published var error: String?

  func create() async {
    isSaving = true; defer { isSaving = false }
    do { try await GoalsAPI.shared.createGoal(name: name, type: type, target: target, due: dueDate) }
    catch { self.error = "\(error)" }
  }
}
