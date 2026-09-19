import XCTest
@testable import WolfGrid

final class BusinessCardSocialLinkTests: XCTestCase {
    func testUsernamesGenerateCompleteLinks() {
        let cases = [
            ("Instagram", "danielphillippe.realty", "https://www.instagram.com/danielphillippe.realty"),
            ("Facebook", "daniel", "https://www.facebook.com/daniel"),
            ("LinkedIn", "daniel", "https://www.linkedin.com/in/daniel"),
            ("TikTok", "@daniel", "https://www.tiktok.com/@daniel"),
            ("YouTube", "@daniel", "https://www.youtube.com/@daniel"),
            ("X", "@daniel", "https://x.com/daniel")
        ]
        for (platform, input, expected) in cases {
            XCTAssertEqual(BusinessCardSocialLink.url(from: input, platform: platform), expected)
            XCTAssertEqual(BusinessCardSocialLink.username(from: expected, platform: platform), input.replacingOccurrences(of: "@", with: ""))
            XCTAssertEqual(BusinessCardSocialLink.url(from: "", platform: platform), "")
            XCTAssertEqual(BusinessCardSocialLink.url(from: "@", platform: platform), "")
        }
    }
    func testPastedAndExistingLinksArePreserved() {
        let instagram = "https://www.instagram.com/danielphillippe.realty/"
        XCTAssertEqual(BusinessCardSocialLink.url(from: instagram, platform: "Instagram"), instagram)
        XCTAssertEqual(BusinessCardSocialLink.username(from: instagram, platform: "Instagram"), "danielphillippe.realty")
        XCTAssertEqual(BusinessCardSocialLink.url(from: "instagram.com/daniel", platform: "Instagram"), "https://instagram.com/daniel")
        XCTAssertEqual(BusinessCardSocialLink.username(from: "https://twitter.com/daniel", platform: "X"), "daniel")
        for (platform, url) in [
            ("LinkedIn", "https://www.linkedin.com/company/wolfgrid/"),
            ("YouTube", "https://www.youtube.com/channel/UC123"),
            ("Facebook", "https://www.facebook.com/profile.php?id=123"),
            ("Instagram", "https://www.instagram.com/daniel/?ref=profile")
        ] {
            XCTAssertEqual(BusinessCardSocialLink.username(from: url, platform: platform), url)
            XCTAssertEqual(BusinessCardSocialLink.url(from: url, platform: platform), url)
        }
        XCTAssertEqual(BusinessCardSocialLink.url(from: "https://example.com", platform: "Website"), "https://example.com")
    }
}
