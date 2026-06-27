import Foundation
import Quick
import Nimble
@testable import ZoukKit

final class AppModelSpec: AsyncSpec {
    override class func spec() {
        describe("AppModel") {
            describe(".baseURL(fromHostInput:)") {
                context("when the input has no scheme") {
                    it("adds http://") {
                        expect(AppModel.baseURL(fromHostInput: "scans.example.com")?.absoluteString)
                            .to(equal("http://scans.example.com"))
                    }
                }

                context("when the input already has an explicit scheme") {
                    it("preserves it") {
                        expect(AppModel.baseURL(fromHostInput: "https://scans.example.com")?.absoluteString)
                            .to(equal("https://scans.example.com"))
                    }
                }

                context("when the input has surrounding whitespace and a port") {
                    it("trims the whitespace and keeps the port") {
                        expect(AppModel.baseURL(fromHostInput: "  10.0.1.111:8080  ")?.absoluteString)
                            .to(equal("http://10.0.1.111:8080"))
                    }
                }

                context("when the input is blank") {
                    it("returns nil") {
                        expect(AppModel.baseURL(fromHostInput: "   ")).to(beNil())
                    }
                }
            }

            // AppModel is @MainActor, so the specs below need Quick's async
            // DSL -- plain QuickSpec's `it` only accepts a synchronous
            // closure (Quick 7 gates async/await support behind the
            // AsyncSpec base class this file uses instead; see
            // Quick/Documentation/en-us/AsyncAwait.md). Each `it` hops to
            // the main actor via `await MainActor.run { ... }`, the pattern
            // that doc recommends for running synchronous, MainActor-bound
            // code from an otherwise-async example -- mirrors the
            // `@MainActor func test...()` isolation the old XCTest cases
            // used, just expressed as an explicit hop instead of a function
            // attribute.

            describe("#toggle(_:)") {
                // Click-to-select / click-again-to-deselect, and that
                // selectedScan looks the selected id back up in the current
                // scan list.
                it("selects then deselects the same scan") {
                    await MainActor.run {
                        let model = AppModel(defaults: makeEphemeralDefaults(), autoConnect: false)
                        let scan = ScanEntry(
                            name: "1782420815.pdf",
                            size: 7,
                            time: "2026-06-25T10:30:00-07:00",
                            url: "/download/1782420815.pdf"
                        )
                        model.scans = [scan]

                        model.toggle(scan)
                        expect(model.selectedScanID).to(equal(scan.id))
                        expect(model.selectedScan).to(equal(scan))

                        model.toggle(scan)
                        expect(model.selectedScanID).to(beNil())
                        expect(model.selectedScan).to(beNil())
                    }
                }
            }

            describe("#changeServer()") {
                it("clears the selection and the scan list") {
                    await MainActor.run {
                        let model = AppModel(defaults: makeEphemeralDefaults(), autoConnect: false)
                        let scan = ScanEntry(
                            name: "1782420815.pdf",
                            size: 7,
                            time: "2026-06-25T10:30:00-07:00",
                            url: "/download/1782420815.pdf"
                        )
                        model.scans = [scan]
                        model.toggle(scan)

                        model.changeServer()

                        expect(model.selectedScanID).to(beNil())
                        expect(model.scans).to(beEmpty())
                    }
                }
            }

            describe("#toggle(_:) and a lingering savedMessage") {
                // The footer can only show one thing at a time: a fresh
                // selection should take over from a lingering "saved to
                // Downloads" message left behind by a previous open(_:),
                // not show both.
                it("clears the saved message on a fresh selection") {
                    await MainActor.run {
                        let model = AppModel(defaults: makeEphemeralDefaults(), autoConnect: false)
                        let scan = ScanEntry(
                            name: "1782420815.pdf",
                            size: 7,
                            time: "2026-06-25T10:30:00-07:00",
                            url: "/download/1782420815.pdf"
                        )
                        model.scans = [scan]
                        model.savedMessage = "1782420815.pdf saved to Downloads."

                        model.toggle(scan)

                        expect(model.savedMessage).to(beNil())
                        expect(model.selectedScanID).to(equal(scan.id))
                    }
                }
            }
        }
    }
}

private func makeEphemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "zouk.tests.\(UUID().uuidString)")!
}
