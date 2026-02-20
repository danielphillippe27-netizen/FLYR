import Foundation
import Combine

@MainActor
final class JoinFlowViewModel: ObservableObject {
    @Published var validated: InviteValidateResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func validate(token: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            validated = try await InviteService.shared.validate(token: token)
        } catch {
            errorMessage = error.localizedDescription
            validated = nil
        }
    }

    func accept(token: String) async throws {
        _ = try await InviteService.shared.accept(token: token)
    }
}
