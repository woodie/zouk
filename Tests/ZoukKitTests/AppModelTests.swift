import XCTest
@testable import ZoukKit

final class AppModelTests: XCTestCase {
    func testBaseURLAddsSchemeWhenMissing() {
        XCTAssertEqual(
            AppModel.baseURL(fromHostInput: "scans.example.com")?.absoluteString,
            "http://scans.example.com"
        )
    }

    func testBaseURLPreservesExplicitScheme() {
        XCTAssertEqual(
            AppModel.baseURL(fromHostInput: "https://scans.example.com")?.absoluteString,
            "https://scans.example.com"
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

    // Click-to-select / click-again-to-deselect, and that selectedScan
    // looks the selected id back up in the current scan list.

    @MainActor
    func testToggleSelectsThenDeselectsSameScan() {
        let model = AppModel(defaults: makeEphemeralDefaults(), autoConnect: false)
        let scan = ScanEntry(name: "1782420815.pdf", size: 7, time: "2026-06-25T10:30:00-07:00", url: "/download/1782420815.pdf")
        model.scans = [scan]

        model.toggle(scan)
        XCTAssertEqual(model.selectedScanID, scan.id)
        XCTAssertEqual(model.selectedScan, scan)

        model.toggle(scan)
        XCTAssertNil(model.selectedScanID)
        XCTAssertNil(model.selectedScan)
    }

    @MainActor
    func testChangeServerClearsSelectionAndScans() {
        let model = AppModel(defaults: makeEphemeralDefaults(), autoConnect: false)
        let scan = ScanEntry(name: "1782420815.pdf", size: 7, time: "2026-06-25T10:30:00-07:00", url: "/download/1782420815.pdf")
        model.scans = [scan]
        model.toggle(scan)

        model.changeServer()

        XCTAssertNil(model.selectedScanID)
        XCTAssertTrue(model.scans.isEmpty)
    }

    // The footer can only show one thing at a time: a fresh selection
    // should take over from a lingering "saved to Downloads" message
    // left behind by a previous open(_:), not show both.

    @MainActor
    func testToggleClearsLingeringSavedMessage() {
        let model = AppModel(defaults: makeEphemeralDefaults(), autoConnect: false)
        let scan = ScanEntry(name: "1782420815.pdf", size: 7, time: "2026-06-25T10:30:00-07:00", url: "/download/1782420815.pdf")
        model.scans = [scan]
        model.savedMessage = "1782420815.pdf saved to Downloads."

        model.toggle(scan)

        XCTAssertNil(model.savedMessage)
        XCTAssertEqual(model.selectedScanID, scan.id)
    }

    private func makeEphemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "zouk.tests.\(UUID().uuidString)")!
    }
}
