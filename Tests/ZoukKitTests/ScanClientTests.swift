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

    // Finder-style de-duplication: re-downloading the same scan should
    // never clobber a file already sitting in Downloads.

    func testUniqueDestinationReturnsPlainNameWhenNothingExists() throws {
        let directory = try makeEmptyTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = ScanClient.uniqueDestination(for: "1782420815.pdf", in: directory)
        XCTAssertEqual(result.lastPathComponent, "1782420815.pdf")
    }

    func testUniqueDestinationAppendsIncrementingCounterOnCollision() throws {
        let directory = try makeEmptyTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data().write(to: directory.appendingPathComponent("1782420815.pdf"))
        try Data().write(to: directory.appendingPathComponent("1782420815 (1).pdf"))

        let result = ScanClient.uniqueDestination(for: "1782420815.pdf", in: directory)
        XCTAssertEqual(result.lastPathComponent, "1782420815 (2).pdf")
    }

    func testUniqueDestinationHandlesNameWithNoExtension() throws {
        let directory = try makeEmptyTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data().write(to: directory.appendingPathComponent("README"))

        let result = ScanClient.uniqueDestination(for: "README", in: directory)
        XCTAssertEqual(result.lastPathComponent, "README (1)")
    }

    private func makeEmptyTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
