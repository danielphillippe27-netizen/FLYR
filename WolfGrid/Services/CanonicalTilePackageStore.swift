import Foundation
import CryptoKit
import MapboxCommon
import Supabase

enum CanonicalTilePackageError: Error { case invalidManifest, downloadFailed, checksumMismatch }

actor CanonicalTilePackageStore {
    static let shared = CanonicalTilePackageStore()
    private var downloads: [String: Task<URL, Error>] = [:]

    /// Offline readiness must describe this exact revision, not an older map
    /// region that happens to exist for the same campaign.
    func hasVerifiedPackage(_ tiles: CanonicalCampaignTiles) -> Bool {
        guard let archive = try? Self.archiveURL(for: tiles),
              let bytes = try? Data(contentsOf: archive, options: .mappedIfSafe),
              bytes.count == tiles.byteLength, Self.hash(bytes) == tiles.sha256,
              (try? CanonicalPMTilesArchive(url: archive)) != nil else { return false }
        guard let pack = tiles.geometryPack else { return true }
        guard let geometry = try? Self.exactGeometryURL(for: tiles),
              let geometryBytes = try? Data(contentsOf: geometry, options: .mappedIfSafe),
              geometryBytes.count == pack.byteLength, Self.hash(geometryBytes) == pack.sha256,
              let reader = try? CanonicalGeometryPack(url: geometry), reader.count == pack.count else { return false }
        return true
    }

    nonisolated static func archiveURL(for tiles: CanonicalCampaignTiles) throws -> URL {
        guard tiles.geometryRevision.count == 64, tiles.geometryRevision.allSatisfy(\.isHexDigit),
              tiles.sha256.count == 64, tiles.byteLength > 0 else { throw CanonicalTilePackageError.invalidManifest }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CanonicalTiles", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(tiles.geometryRevision)-\(tiles.sha256).pmtiles")
    }

    func download(_ tiles: CanonicalCampaignTiles) async throws -> URL {
        let key = "pmtiles:\(tiles.geometryRevision):\(tiles.sha256)"
        if let task = downloads[key] { return try await task.value }
        let task = Task<URL, Error> {
            let destination = try Self.archiveURL(for: tiles)
            if FileManager.default.fileExists(atPath: destination.path) {
                let bytes = try Data(contentsOf: destination, options: .mappedIfSafe)
                if bytes.count == tiles.byteLength && Self.hash(bytes) == tiles.sha256 {
                    CanonicalTileHTTP.shared.register(tiles, file: destination)
                    return destination
                }
            }
            guard let url = URL(string: tiles.archiveURL), url.scheme == "https" else { throw CanonicalTilePackageError.invalidManifest }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
            request.setValue("Bearer \(try await SupabaseManager.shared.client.auth.session.accessToken)", forHTTPHeaderField: "Authorization")
            let (temporary, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CanonicalTilePackageError.downloadFailed }
            let bytes = try Data(contentsOf: temporary, options: .mappedIfSafe)
            guard bytes.count == tiles.byteLength, Self.hash(bytes) == tiles.sha256 else { throw CanonicalTilePackageError.checksumMismatch }
            _ = try CanonicalPMTilesArchive(url: temporary)
            // Atomic replacement only after checksum and format validation. Other
            // revisions remain intact while the current package is downloading.
            try bytes.write(to: destination, options: .atomic)
            CanonicalTileHTTP.shared.register(tiles, file: destination)
            return destination
        }
        downloads[key] = task
        defer { downloads[key] = nil }
        return try await task.value
    }

    nonisolated static func exactGeometryURL(for tiles: CanonicalCampaignTiles) throws -> URL {
        guard let pack = tiles.geometryPack, pack.sha256.count == 64, pack.sha256.allSatisfy(\.isHexDigit),
              pack.byteLength > 0, pack.count >= 0 else { throw CanonicalTilePackageError.invalidManifest }
        let archive = try archiveURL(for: tiles)
        return archive.deletingLastPathComponent().appendingPathComponent("\(tiles.geometryRevision)-\(pack.sha256).wgp")
    }

    func downloadExactGeometry(_ tiles: CanonicalCampaignTiles) async throws -> URL {
        guard let pack = tiles.geometryPack else { throw CanonicalTilePackageError.invalidManifest }
        let key = "wgp:\(tiles.geometryRevision):\(pack.sha256)"
        if let task = downloads[key] { return try await task.value }
        let task = Task<URL, Error> {
            let destination = try Self.exactGeometryURL(for: tiles)
            if FileManager.default.fileExists(atPath: destination.path),
               let bytes = try? Data(contentsOf: destination, options: .mappedIfSafe),
               bytes.count == pack.byteLength, Self.hash(bytes) == pack.sha256,
               let reader = try? CanonicalGeometryPack(url: destination), reader.count == pack.count {
                return destination
            }
            guard let url = URL(string: pack.url), url.scheme == "https" else { throw CanonicalTilePackageError.invalidManifest }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
            request.setValue("Bearer \(try await SupabaseManager.shared.client.auth.session.accessToken)", forHTTPHeaderField: "Authorization")
            let (temporary, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CanonicalTilePackageError.downloadFailed }
            let bytes = try Data(contentsOf: temporary, options: .mappedIfSafe)
            guard bytes.count == pack.byteLength, Self.hash(bytes) == pack.sha256 else { throw CanonicalTilePackageError.checksumMismatch }
            guard try CanonicalGeometryPack(url: temporary).count == pack.count else { throw CanonicalTilePackageError.invalidManifest }
            try bytes.write(to: destination, options: .atomic)
            return destination
        }
        downloads[key] = task
        defer { downloads[key] = nil }
        return try await task.value
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

/// The SDK continues to request the same authenticated XYZ URLs. A verified
/// offline package answers those requests locally, including after app restart.
final class CanonicalTileHTTP: NSObject, HttpServiceInterceptorInterface, @unchecked Sendable {
    static let shared = CanonicalTileHTTP()
    private let lock = NSLock()
    private var archives: [String: CanonicalPMTilesArchive] = [:]
    private var registeredPrefixes = Set<String>()
    private let queue = DispatchQueue(label: "app.wolfgrid.canonical-tiles", qos: .userInitiated, attributes: .concurrent)

    private override init() {
        super.init()
        HttpServiceFactory.setHttpServiceInterceptorForInterceptor(self)
    }

    @discardableResult func registerIfPresent(_ tiles: CanonicalCampaignTiles) -> Bool {
        if let prefix = tiles.tileURLTemplate.components(separatedBy: "/{z}").first {
            lock.lock(); registeredPrefixes.insert(prefix); lock.unlock()
        }
        guard let file = try? CanonicalTilePackageStore.archiveURL(for: tiles), FileManager.default.fileExists(atPath: file.path) else { return false }
        return register(tiles, file: file)
    }

    @discardableResult func register(_ tiles: CanonicalCampaignTiles, file: URL) -> Bool {
        guard let prefix = tiles.tileURLTemplate.components(separatedBy: "/{z}").first,
              let reader = try? CanonicalPMTilesArchive(url: file) else { return false }
        lock.lock()
        if archives.count >= 8, archives[prefix] == nil, let oldest = archives.keys.first { archives.removeValue(forKey: oldest) }
        registeredPrefixes.insert(prefix); archives[prefix] = reader; lock.unlock()
        return true
    }

    func onRequest(for request: HttpRequest, continuation: @escaping HttpServiceInterceptorRequestContinuation) {
        guard let url = URL(string: request.url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            continuation(.fromHttpRequest(request)); return
        }
        components.query = nil; components.fragment = nil
        let parts = url.pathComponents
        guard parts.count >= 4, let z = Int(parts[parts.count - 3]), let x = Int(parts[parts.count - 2]),
              let y = Int(parts.last!.replacingOccurrences(of: ".mvt", with: "")) else { continuation(.fromHttpRequest(request)); return }
        components.path = parts.dropLast(3).joined(separator: "/").replacingOccurrences(of: "//", with: "/")
        let key = components.string ?? ""
        lock.lock(); let archive = archives[key]; let isRegistered = registeredPrefixes.contains(key); lock.unlock()
        #if DEBUG
        if url.host == "canonical-tiles.wolfgrid.invalid" { print("CANONICAL_TILE_HTTP z=\(z) x=\(x) y=\(y) matched=\(archive != nil)") }
        #endif
        guard let archive else {
            guard isRegistered else { continuation(.fromHttpRequest(request)); return }
            // Refresh the bearer token for every network request. A campaign can
            // remain open beyond the lifetime of the token used at map startup.
            Task {
                if let session = try? await SupabaseManager.shared.client.auth.session {
                    var headers = request.headers
                    headers["Authorization"] = "Bearer \(session.accessToken)"
                    request.headers = headers
                }
                continuation(.fromHttpRequest(request))
            }
            return
        }
        queue.async {
            do {
                let data = try archive.tile(z: z, x: x, y: y)
                #if DEBUG
                if url.host == "canonical-tiles.wolfgrid.invalid" { print("CANONICAL_TILE_BYTES z=\(z) x=\(x) y=\(y) bytes=\(data?.count ?? 0)") }
                #endif
                let result = HttpResponseData(headers: ["content-type": "application/vnd.mapbox-vector-tile"], code: data == nil ? 204 : 200, data: data ?? Data())
                continuation(.fromHttpResponse(HttpResponse(identifier: 0, request: request, result: .success(result))))
            } catch {
                // A corrupt archive is a failed request, never an empty tile.
                let result = HttpResponseData(headers: [:], code: 503, data: Data())
                continuation(.fromHttpResponse(HttpResponse(identifier: 0, request: request, result: .success(result))))
            }
        }
    }

    func onResponse(for response: HttpResponse, continuation: @escaping HttpServiceInterceptorResponseContinuation) { continuation(response) }
}
