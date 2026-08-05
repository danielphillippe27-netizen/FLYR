import XCTest

final class NativeAuthE2ETests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testIsolatedQaUserCanSignInAndReachDashboard() throws {
        let environment = ProcessInfo.processInfo.environment
        let testBundle = Bundle(for: Self.self)
        func setting(_ name: String) -> String? {
            environment[name] ?? testBundle.object(forInfoDictionaryKey: name) as? String
        }
        let supabaseURL = try XCTUnwrap(setting("QA_SUPABASE_URL"))
        let anonKey = try XCTUnwrap(setting("QA_SUPABASE_ANON_KEY"))
        let email = try XCTUnwrap(setting("QA_IOS_EMAIL"))
        let password = try XCTUnwrap(setting("QA_IOS_PASSWORD"))
        let workspaceID = try XCTUnwrap(setting("QA_WORKSPACE_ID"))
        let campaignID = try XCTUnwrap(setting("QA_CAMPAIGN_ID"))
        let sessionID = try XCTUnwrap(setting("QA_SESSION_ID"))
        let latitude = try XCTUnwrap(setting("QA_LATITUDE"))
        let longitude = try XCTUnwrap(setting("QA_LONGITUDE"))
        XCTAssertTrue(["127.0.0.1", "localhost", "::1"].contains(URL(string: supabaseURL)?.host ?? ""))

        let app = XCUIApplication()
        app.launchEnvironment = [
            "WOLFGRID_E2E": "1",
            "WOLFGRID_E2E_SUPABASE_URL": supabaseURL,
            "WOLFGRID_E2E_SUPABASE_ANON_KEY": anonKey,
            "WOLFGRID_E2E_WORKSPACE_ID": workspaceID,
            "WOLFGRID_E2E_CAMPAIGN_ID": campaignID,
            "WOLFGRID_E2E_SESSION_ID": sessionID,
            "WOLFGRID_E2E_LATITUDE": latitude,
            "WOLFGRID_E2E_LONGITUDE": longitude
        ]
        app.launch()

        let emailField = app.textFields["auth.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 20))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["auth.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["auth.continue"].tap()

        XCTAssertTrue(app.otherElements["route.dashboard"].waitForExistence(timeout: 30))
        let publishPresence = app.buttons["e2e.publish.presence"]
        XCTAssertTrue(publishPresence.waitForExistence(timeout: 10))
        XCTAssertTrue(publishPresence.isHittable)
        publishPresence.tap()
        let didPublish = publishPresence.waitForNonExistence(timeout: 15)
        if !didPublish {
            let error = app.staticTexts["e2e.presence.error"]
            let errorMessage = error.exists ? error.label : "no in-app error was reported"
            XCTFail("Presence publish did not complete: \(errorMessage)")
        }
    }
}
