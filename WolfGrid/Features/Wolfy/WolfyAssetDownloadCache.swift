import Foundation
import CryptoKit

/// Downloads are opt-in via the bundled, versioned manifest, never an arbitrary catalog URL.
actor WolfyAssetDownloadCache {
    static let shared=WolfyAssetDownloadCache()
    private let limit=64*1024*1024
    func file(name:String,version:Int,info:WolfyAssetManifest.FileInfo) async throws -> URL {
        guard info.bytes<=10*1024*1024,let source=info.url,let url=URL(string:source),url.scheme=="https",
              !name.contains("/"),!name.contains("..") else { throw CocoaError(.fileReadUnsupportedScheme) }
        let directory=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("WolfyAssets/v\(version)",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let destination=directory.appendingPathComponent(info.sha256+"-"+name)
        if FileManager.default.fileExists(atPath:destination.path) { return destination }
        let (temporary,response)=try await URLSession.shared.download(from:url)
        defer { try? FileManager.default.removeItem(at:temporary) }
        guard let http=response as? HTTPURLResponse,http.statusCode==200,http.url?.host==url.host else { throw URLError(.badServerResponse) }
        let data=try Data(contentsOf:temporary,options:.mappedIfSafe)
        guard data.count==info.bytes,SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==info.sha256 else { throw CocoaError(.fileReadCorruptFile) }
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey,.contentModificationDateKey])
        var total=files.reduce(0){$0+((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0)}
        for file in files.sorted(by:{$0.lastPathComponent<$1.lastPathComponent}) where total+info.bytes>limit {
            total -= (try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at:file)
        }
        try FileManager.default.moveItem(at:temporary,to:destination)
        return destination
    }
}
