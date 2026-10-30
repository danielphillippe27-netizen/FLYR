// Run with StandardCampaignClusterLayout.swift and StandardCampaignClusterLayoutTests.swift.
// The same regression cases run in XCTest and directly on macOS without a simulator.
import Foundation

// Assertion adapter for running the production regression cases without loading
// the iOS application or the macOS XCTest bundle runner.
class XCTestCase {}
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value(), "Expected true", file: file, line: line)
}
func XCTAssertNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value() == nil, "Expected nil", file: file, line: line)
}
func XCTAssertNotNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value() != nil, "Expected a value", file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T,
                                 file: StaticString = #file, line: UInt = #line) {
    precondition(lhs() == rhs(), "Values differ", file: file, line: line)
}
func XCTUnwrap<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
    precondition(value != nil, "Expected a value", file: file, line: line)
    return value!
}

@main
struct StandardCampaignMapRegressionRunner {
    static func main() throws {
        let tests = StandardCampaignClusterLayoutTests()
        for (name, test) in StandardCampaignClusterLayoutTests.standaloneTests {
            try test(tests)()
            print("PASS: \(name)")
        }
        let drafts = StandardCampaignPinDraftTests()
        for (name, test) in StandardCampaignPinDraftTests.standaloneTests {
            try test(drafts)()
            print("PASS: \(name)")
        }
    }
}
