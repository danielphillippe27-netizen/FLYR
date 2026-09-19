import Foundation

/// The editor accepts handles; persisted card content always uses full URLs.
enum BusinessCardSocialLink {
    static func prefix(for platform: String) -> String? {
        switch platform {
        case "Instagram": return "https://www.instagram.com/"
        case "Facebook": return "https://www.facebook.com/"
        case "LinkedIn": return "https://www.linkedin.com/in/"
        case "TikTok": return "https://www.tiktok.com/@"
        case "YouTube": return "https://www.youtube.com/@"
        case "X": return "https://x.com/"
        default: return nil
        }
    }

    static func url(from input: String, platform: String) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        guard let prefix = prefix(for: platform) else { return value }
        // Keep pasted URLs intact, including LinkedIn company pages and YouTube channels.
        if value.lowercased().hasPrefix("https://") { return value }
        if value.lowercased().hasPrefix("http://") { return "https://" + value.dropFirst(7) }
        let hosts = ["instagram.com/", "facebook.com/", "linkedin.com/", "tiktok.com/", "youtube.com/", "youtu.be/", "x.com/", "twitter.com/"]
        let withoutWWW = value.lowercased().hasPrefix("www.") ? String(value.dropFirst(4)) : value
        if hosts.contains(where: { withoutWWW.lowercased().hasPrefix($0) }) { return "https://" + value }
        let handle = value.trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
        return handle.isEmpty ? "" : prefix + handle
    }

    static func username(from url: String, platform: String) -> String {
        guard let prefix = prefix(for: platform),
              let actual = URLComponents(string: url), let expected = URLComponents(string: prefix),
              let host = actual.host?.lowercased(), let expectedHost = expected.host?.lowercased() else { return url }
        func canonicalHost(_ value: String) -> String {
            let bare = value.hasPrefix("www.") ? String(value.dropFirst(4)) : value
            return bare == "twitter.com" ? "x.com" : bare
        }
        guard canonicalHost(host) == canonicalHost(expectedHost),
              actual.percentEncodedPath.hasPrefix(expected.percentEncodedPath),
              actual.query == nil, actual.fragment == nil, actual.user == nil, actual.password == nil else { return url }
        let handle = String(actual.percentEncodedPath.dropFirst(expected.percentEncodedPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Legacy paths remain editable as full links rather than being turned into handles.
        guard !handle.contains("/"), !handle.contains("?") else { return url }
        return handle.removingPercentEncoding ?? handle
    }
}
