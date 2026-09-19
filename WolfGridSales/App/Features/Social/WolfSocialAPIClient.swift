import AuthenticationServices
import Combine
import Foundation
import Supabase
import UIKit

enum WolfSocialAPIError: LocalizedError {
    case invalidResponse
    case server(String)
    var errorDescription: String? { switch self { case .invalidResponse: "WolfSocial returned an invalid response."; case .server(let message): message } }
}

actor WolfSocialAPIClient {
    static let shared = WolfSocialAPIClient()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var workspaceID: String? = UserDefaults.standard.string(forKey: "wolfsocial.workspace.id")

    private struct ErrorEnvelope: Decodable { let error: String? }
    private struct WorkspaceEnvelope: Decodable { let workspace: WolfSocialWorkspace; let canCreateLead: Bool? }
    private struct ConnectionsEnvelope: Decodable { let connections: [WolfSocialConnection]; let socialWorkspace: WolfSocialWorkspace?; let providerAvailability: [String: WolfSocialProviderAvailability]? }
    private struct PostsEnvelope: Decodable { let posts: [WolfSocialPost] }
    private struct AssetsEnvelope: Decodable { let assets: [WolfSocialMediaAsset] }
    private struct AssetEnvelope: Decodable { let asset: WolfSocialMediaAsset }
    private struct ThreadsEnvelope: Decodable { let threads: [WolfSocialThread] }
    private struct OAuthEnvelope: Decodable { let authorizeUrl: URL }
    private struct UploadEnvelope: Decodable { let upload: UploadReceipt }
    private struct CreatorInfoEnvelope: Decodable { let creatorInfo: WolfSocialTikTokCreatorInfo }
    private struct UploadReceipt: Decodable { let signedUrl: URL; let storagePath: String; let mimeType: String; let byteSize: Int64; let originalName: String }
    private struct ReplyBody: Encodable { let body: String }
    private struct WolfeyBody: Encodable { let task: String; let source: String }
    private struct WolfeyEnvelope: Decodable { let suggestions: [String]; let requiresApproval: Bool }
    private struct PostActionBody: Encodable { let action: String }
    private struct UploadRequest: Encodable { let fileName: String; let mimeType: String; let byteSize: Int64 }
    private struct UploadComplete: Encodable { let storagePath: String; let mimeType: String; let byteSize: Int64; let originalName: String; let durationSeconds: Double? }

    func loadWorkspace() async throws -> (WolfSocialWorkspace, Bool) {
        let envelope: WorkspaceEnvelope = try await request(path: "/api/social/workspace")
        workspaceID = envelope.workspace.id
        UserDefaults.standard.set(envelope.workspace.id, forKey: "wolfsocial.workspace.id")
        return (envelope.workspace, envelope.canCreateLead ?? false)
    }

    func connections() async throws -> ([WolfSocialConnection], [String: WolfSocialProviderAvailability]) {
        let envelope: ConnectionsEnvelope = try await request(path: "/api/social/connections")
        if let id = envelope.socialWorkspace?.id { workspaceID = id; UserDefaults.standard.set(id, forKey: "wolfsocial.workspace.id") }
        return (envelope.connections, envelope.providerAvailability ?? [:])
    }
    func posts() async throws -> [WolfSocialPost] { let value: PostsEnvelope = try await request(path: "/api/social/posts"); return value.posts }
    func media() async throws -> [WolfSocialMediaAsset] { let value: AssetsEnvelope = try await request(path: "/api/social/media"); return value.assets }
    func inbox() async throws -> [WolfSocialThread] { let value: ThreadsEnvelope = try await request(path: "/api/social/inbox"); return value.threads }
    func analytics() async throws -> WolfSocialAnalytics { try await request(path: "/api/social/analytics") }

    func createPost(_ post: WolfSocialPostRequest) async throws {
        let _: EmptySuccess = try await request(path: "/api/social/posts", method: "POST", body: post)
    }

    func reply(threadID: String, body: String) async throws {
        let _: EmptySuccess = try await request(path: "/api/social/inbox/\(threadID)/reply", method: "POST", body: ReplyBody(body: body))
    }

    func createLead(contactID: String) async throws -> String? {
        struct LeadEnvelope: Decodable { let leadId: String? }
        let value: LeadEnvelope = try await request(path: "/api/social/contacts/\(contactID)/create-lead", method: "POST")
        return value.leadId
    }

    func wolfey(task: String, source: String) async throws -> [String] {
        let value: WolfeyEnvelope = try await request(path: "/api/social/wolfey", method: "POST", body: WolfeyBody(task: task, source: source))
        return value.suggestions
    }

    func postAction(postID: String, action: String) async throws {
        let _: EmptySuccess = try await request(path: "/api/social/posts/\(postID)", method: "PATCH", body: PostActionBody(action: action))
    }

    func oauthURL(platform: WolfSocialPlatform) async throws -> URL {
        let value: OAuthEnvelope = try await request(path: "/api/social/oauth/\(platform.rawValue)/start", method: "POST")
        return value.authorizeUrl
    }

    func tikTokCreatorInfo(connectionID: String) async throws -> WolfSocialTikTokCreatorInfo {
        let value: CreatorInfoEnvelope = try await request(path: "/api/social/connections/\(connectionID)/creator-info")
        return value.creatorInfo
    }

    func disconnect(connectionID: String) async throws {
        let _: EmptySuccess = try await request(path: "/api/social/connections/\(connectionID)", method: "DELETE")
    }

    func uploadMedia(data: Data, fileName: String, mimeType: String, durationSeconds: Double? = nil, progress: @escaping @Sendable (Double) async -> Void) async throws -> WolfSocialMediaAsset {
        await progress(0.1)
        let size = Int64(data.count)
        let prepared: UploadEnvelope = try await request(path: "/api/social/media/upload-url", method: "POST", body: UploadRequest(fileName: fileName, mimeType: mimeType, byteSize: size))
        try Task.checkCancellation()
        await progress(0.25)
        var upload = URLRequest(url: prepared.upload.signedUrl)
        upload.httpMethod = "PUT"
        upload.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        upload.setValue("false", forHTTPHeaderField: "x-upsert")
        let (_, response) = try await URLSession.shared.upload(for: upload, from: data)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw WolfSocialAPIError.server("Media upload failed.") }
        try Task.checkCancellation()
        await progress(0.85)
        let completed: AssetEnvelope = try await request(path: "/api/social/media/complete", method: "POST", body: UploadComplete(storagePath: prepared.upload.storagePath, mimeType: mimeType, byteSize: size, originalName: fileName, durationSeconds: durationSeconds))
        await progress(1)
        return completed.asset
    }

    private struct EmptySuccess: Decodable {}

    private func request<Response: Decodable>(path: String, method: String = "GET") async throws -> Response {
        try await request(path: path, method: method, bodyData: nil)
    }

    private func request<Response: Decodable, Body: Encodable>(path: String, method: String = "GET", body: Body) async throws -> Response {
        try await request(path: path, method: method, bodyData: encoder.encode(body))
    }

    private func request<Response: Decodable>(path: String, method: String, bodyData: Data?) async throws -> Response {
        guard let url = URL(string: path, relativeTo: Config.backendAPIURL)?.absoluteURL else { throw WolfSocialAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let workspaceID { request.setValue(workspaceID, forHTTPHeaderField: "X-Social-Workspace-ID") }
        if let bodyData { request.httpBody = bodyData; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try await authorized(request)
    }

    private func authorized<Response: Decodable>(_ original: URLRequest) async throws -> Response {
        var request = original
        let session = try await SupabaseManager.shared.client.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await URLSession.shared.data(for: request)
        guard var http = response as? HTTPURLResponse else { throw WolfSocialAPIError.invalidResponse }
        if http.statusCode == 401 {
            let refreshed = try await SupabaseManager.shared.client.auth.refreshSession()
            KeychainAuthStorage.saveSession(accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken)
            request.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await URLSession.shared.data(for: request)
            guard let retryHTTP = response as? HTTPURLResponse else { throw WolfSocialAPIError.invalidResponse }
            http = retryHTTP
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).error) ?? "WolfSocial request failed (\(http.statusCode))."
            throw WolfSocialAPIError.server(message)
        }
        if Response.self == EmptySuccess.self, (try? decoder.decode(Response.self, from: data)) == nil {
            return EmptySuccess() as! Response
        }
        return try decoder.decode(Response.self, from: data)
    }
}

@MainActor
final class WolfSocialOAuthSession: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var isConnecting = false
    private var session: ASWebAuthenticationSession?

    func connect(_ platform: WolfSocialPlatform) {
        isConnecting = true
        Task {
            do {
                let url = try await WolfSocialAPIClient.shared.oauthURL(platform: platform)
                let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "wolfgridsales") { [weak self] callback, error in
                    Task { @MainActor in
                        self?.isConnecting = false
                        if let callback { NotificationCenter.default.post(name: .wolfSocialOAuthCompleted, object: callback) }
                        else if let error { NotificationCenter.default.post(name: .wolfSocialOAuthCompleted, object: error) }
                    }
                }
                auth.presentationContextProvider = self
                auth.prefersEphemeralWebBrowserSession = false
                session = auth
                auth.start()
            } catch {
                isConnecting = false
                NotificationCenter.default.post(name: .wolfSocialOAuthCompleted, object: error)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
