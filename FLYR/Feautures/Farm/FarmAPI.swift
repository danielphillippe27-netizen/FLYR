import Foundation

struct FarmAPI {
  static let shared = FarmAPI()
  func createFarm(name: String, areaLabel: String, frequencyDays: Int, phases: [String]) async throws {
    // TODO: call Supabase RPC or REST to create farm_plans + farm_phases
    // For now, mock:
    try await Task.sleep(nanoseconds: 200_000_000)
  }
}







