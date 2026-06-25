import XCTest
@testable import ZoukKit

final class AppModelTests: XCTestCase {
    func testBaseURLAddsSchemeWhenMissing() {
        XCTAssertEqual(
            AppModel.baseURL(fromHostInput: "scans.netpress.com")?.absoluteString,
            "http://scans.netpress.com"
        )
    }

    func testBaseURLPreservesExplicitScheme() {
        XCTAssertEqual(
            AppModel.baseURL(fromHostInput: "https://scans.netpress.com")?.absoluteString,
            "https://scans.netpress.com"
        )
    }

    func testBaseURLTrimsWhitespaceAndKeepsPort() {
        XCTAssertEqual(
            AppModel.baseURL(fromHostInput: "  10.0.1.111:8080  ")?.absoluteString,
            "http://10.0.1.111:8080"
        )
    }

    func testBaseURLNilForEmptyInput() {
        XCTAssertNil(AppModel.baseURL(fromHostInput: "   "))
    }
}
