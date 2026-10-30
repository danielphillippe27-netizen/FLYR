import Foundation

/// Shared validation for native Phone, Messages and Mail handoffs.
enum ContactCommunication {
    static func phoneNumber(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never silently turn an extension into part of the destination number.
        let base = trimmed.components(separatedBy: CharacterSet(charactersIn: ";,#")).first ?? trimmed
        let lowered = base.lowercased()
        let number = lowered.components(separatedBy: "ext").first?.components(separatedBy: "x").first ?? lowered
        let digits = number.filter { $0.isASCII && $0.isNumber }
        guard (7...15).contains(digits.count) else { return nil }
        return (trimmed.hasPrefix("+") ? "+" : "") + digits
    }

    static func phoneURL(_ raw: String?, text: Bool = false) -> URL? {
        guard let number = phoneNumber(raw) else { return nil }
        return URL(string: "\(text ? "sms" : "tel"):\(number)")
    }

    static func emailURL(_ raw: String?) -> URL? {
        guard let email = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              email.split(separator: "@", omittingEmptySubsequences: false).count == 2,
              !email.hasPrefix("@"), !email.hasSuffix("@"),
              !email.contains(where: { $0.isWhitespace }),
              email.rangeOfCharacter(from: CharacterSet(charactersIn: "?,;<>")) == nil else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        return components.url
    }
}
