import XCTest
@testable import ZoukKit

final class ScanClientTests: XCTestCase {
    // ScanClient resolves "/download/:filename" (an absolute path) against
    // baseURL for the actual GET. Pin down that URL's relativeTo: resolution
    // behaves the way the implementation assumes -- an absolute path
    // replaces the base's whole path, it doesn't get appended to it.
    func testDownloadPathResolvesAgainstBaseAsAbsolutePath() {
        let base = URL(string: "http://scans.netpress.com")!
        let resolved = URL(string: "/download/1779907271.pdf", relativeTo: base)?.absoluteURL
        XCTAssertEqual(resolved?.absoluteString, "http://scans.netpress.com/download/1779907271.pdf")
    }

    func testFetchScansURLAppendsToHostWithPort() {
        let base = URL(string: "http://10.0.1.111:8080")!
        XCTAssertEqual(base.appendingPathComponent("scans.json").absoluteString, "http://10.0.1.111:8080/scans.json")
    }
}
