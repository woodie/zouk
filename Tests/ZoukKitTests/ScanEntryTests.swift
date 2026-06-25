import XCTest
@testable import ZoukKit

final class ScanEntryTests: XCTestCase {
    func testDecodesServerJSON() throws {
        let json = Data("""
        [{"name":"1779907271.pdf","size":7,"time":"2026-06-25T10:30:00-07:00","url":"/download/1779907271.pdf"}]
        """.utf8)

        let scans = try JSONDecoder().decode([ScanEntry].self, from: json)

        XCTAssertEqual(scans.count, 1)
        XCTAssertEqual(scans[0].name, "1779907271.pdf")
        XCTAssertEqual(scans[0].size, 7)
        XCTAssertEqual(scans[0].url, "/download/1779907271.pdf")
        XCTAssertNotNil(scans[0].downloadedAt)
    }

    func testFormattedSizeIsHumanReadable() {
        let scan = ScanEntry(name: "a.pdf", size: 1_500_000, time: "2026-06-25T10:30:00-07:00", url: "/download/a.pdf")
        XCTAssertTrue(scan.formattedSize.contains("MB"))
    }
}
