import Combine
import Foundation
import Supabase

/// Holds current user's CRM connection status (e.g. FUB) from crm_connections.
/// Refresh after ConnectFUBView success so IntegrationsView shows "Connected ●".
@MainActor
final class CRMConnectionStore: ObservableObject {
    static let shared = CRMConnectionStore()

    @Published private(set) var connections: [CRMConnection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let client = SupabaseManager.shared.client
    private init() {}

    func connection(for provider: String) -> CRMConnection? {
        connections.first { $0.provider == provider }
    }

    var isFUBConnected: Bool {
        connection(for: "fub")?.isConnected ?? false
    }

    var fubConnection: CRMConnection? {
        connection(for: "fub")
    }

    /// Call on appear and after successful FUB connect.
    func refresh(userId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await client
                .from("crm_connections")
                .select()
                .eq("user_id", value: userId)
                .execute()

            let decoder = JSONDecoder.supabaseDates
            connections = try decoder.decode([CRMConnection].self, from: response.data)
        } catch {
            self.error = error.localizedDescription
            connections = []
        }
    }
}
