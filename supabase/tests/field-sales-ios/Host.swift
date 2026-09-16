import SwiftUI
import Supabase
import Combine
struct TestUser { let id: UUID }
final class AuthManager: ObservableObject {
 static let shared = AuthManager()
 @Published var user: TestUser? = TestUser(id: UUID(uuidString:"00000000-0000-0000-0000-000000000001")!)
}
final class WorkspaceContext: ObservableObject {
 static let shared = WorkspaceContext()
 @Published var workspaceId: UUID? = UUID(uuidString:"00000000-0000-0000-0000-000000000010")!
}
final class SupabaseManager {
 static let shared = SupabaseManager()
 let client = SupabaseClient(supabaseURL: URL(string:"http://127.0.0.1:4318")!,supabaseKey:"local-test-only",options:.init(auth: .init(storage: AcceptanceSessionStorage()), global:.init(headers:["X-Test-Actor":"1"])))
}
@main struct SalesAcceptanceApp: App {
 var body: some Scene { WindowGroup { NavigationStack { Host() } } }
}
struct Host: View {
 @State private var snapshot: FieldSalesSnapshot?
 var body: some View {
  ScrollView { VStack(spacing:20) {
   Text("Local Sales Acceptance").font(.title)
   if snapshot != nil { FieldSalesHomeModule() }
   NavigationLink("Open Sales") { FieldSalesRootView() }
   NavigationLink("Open sales leaderboard") { FieldSalesRootView(leaderboardOnly:true) }
  }.padding() }
  .task { await load() }
  .onReceive(NotificationCenter.default.publisher(for:.fieldSalesChanged)) { _ in Task { await load() } }
 }
 func load() async { snapshot = try? await FieldSalesService.snapshot(.init(p_workspace:WorkspaceContext.shared.workspaceId!)) }
}

// Unsigned simulator harnesses cannot rely on keychain entitlements.
final class AcceptanceSessionStorage: AuthLocalStorage, @unchecked Sendable {
 private let lock = NSLock()
 private var values: [String: Data] = [:]
 func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
 func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
 func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: key) }
}
