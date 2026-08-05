import Foundation

struct CountryOption: Identifiable, Hashable {
    let code: String
    let name: String
    let flag: String

    var id: String { code }
    var label: String { "\(flag) \(name)" }
}

enum CountryOptions {
    private static let codes = [
        "AF","AX","AL","DZ","AS","AD","AO","AI","AQ","AG","AR","AM","AW","AU","AT","AZ",
        "BS","BH","BD","BB","BY","BE","BZ","BJ","BM","BT","BO","BQ","BA","BW","BV","BR",
        "IO","BN","BG","BF","BI","CV","KH","CM","CA","KY","CF","TD","CL","CN","CX","CC",
        "CO","KM","CG","CD","CK","CR","CI","HR","CU","CW","CY","CZ","DK","DJ","DM","DO",
        "EC","EG","SV","GQ","ER","EE","SZ","ET","FK","FO","FJ","FI","FR","GF","PF","TF",
        "GA","GM","GE","DE","GH","GI","GR","GL","GD","GP","GU","GT","GG","GN","GW","GY",
        "HT","HM","VA","HN","HK","HU","IS","IN","ID","IR","IQ","IE","IM","IL","IT","JM",
        "JP","JE","JO","KZ","KE","KI","KP","KR","KW","KG","LA","LV","LB","LS","LR","LY",
        "LI","LT","LU","MO","MG","MW","MY","MV","ML","MT","MH","MQ","MR","MU","YT","MX",
        "FM","MD","MC","MN","ME","MS","MA","MZ","MM","NA","NR","NP","NL","NC","NZ","NI",
        "NE","NG","NU","NF","MK","MP","NO","OM","PK","PW","PS","PA","PG","PY","PE","PH",
        "PN","PL","PT","PR","QA","RE","RO","RU","RW","BL","SH","KN","LC","MF","PM","VC",
        "WS","SM","ST","SA","SN","RS","SC","SX","SG","SK","SI","SB","SO","ZA","GS","SS",
        "ES","LK","SD","SR","SJ","SE","CH","SY","TW","TJ","TZ","TH","TL","TG","TK","TO",
        "TT","TN","TR","TM","TC","TV","UG","UA","AE","GB","US","UM","UY","UZ","VU","VE",
        "VN","VG","VI","WF","EH","YE","ZM","ZW"
    ]

    static let all: [CountryOption] = {
        let locale = Locale(identifier: "en_US")
        return codes.map { code in
            CountryOption(
                code: code,
                name: locale.localizedString(forRegionCode: code) ?? code,
                flag: flag(for: code)
            )
        }
        .sorted { left, right in
            left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }()

    static func flag(for countryCode: String?) -> String {
        let normalized = (countryCode ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard normalized.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil else {
            return ""
        }

        return normalized.unicodeScalars.compactMap { scalar -> String? in
            UnicodeScalar(127397 + scalar.value).map(String.init)
        }.joined()
    }

    static func normalize(_ countryCode: String?) -> String? {
        let normalized = (countryCode ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return codes.contains(normalized) ? normalized : nil
    }
}
