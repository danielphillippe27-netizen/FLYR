import Foundation

struct GoalsAPI {
  static let shared = GoalsAPI()
  func createGoal(name: String, type: String, target: Int, due: Date) async throws {
    // TODO: Supabase insert into goals table
    try await Task.sleep(nanoseconds: 200_000_000)
  }
}







