import XCTest
import Supabase
import Auth
@testable import WolfGrid

@MainActor
final class AuthSessionRestoreTests: XCTestCase {
    func testServerOutageRetainsCredentialsButRejectedSessionDoesNot() throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/auth"))
        func apiError(_ status: Int) throws -> Auth.AuthError {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            return .api(message: "test", errorCode: .unknown, underlyingData: Data(), underlyingResponse: response)
        }
        XCTAssertTrue(AuthManager.isTransientSessionRestoreFailure(try apiError(521)))
        XCTAssertTrue(AuthManager.isTransientSessionRestoreFailure(try apiError(429)))
        XCTAssertTrue(AuthManager.isTransientSessionRestoreFailure(URLError(.timedOut)))
        XCTAssertFalse(AuthManager.isTransientSessionRestoreFailure(try apiError(401)))
        XCTAssertFalse(AuthManager.isTransientSessionRestoreFailure(Auth.AuthError.sessionMissing))
    }
}
