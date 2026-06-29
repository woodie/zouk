import Foundation
import Quick
import Nimble
@testable import ZoukKit

final class AppModelSpec: AsyncSpec {
    override class func spec() {
        describe("AppModel") {
            describe(".baseURL(fromHostInput:)") {
                var input: String!
                var result: URL!

                context("when the input has no scheme") {
                    beforeEach {
                        input = "scans.example.com"
                        result = AppModel.baseURL(fromHostInput: input)
                    }

                    it("adds http://") {
                        expect(result?.absoluteString).to(equal("http://scans.example.com"))
                    }
                }

                context("when the input already has an explicit scheme") {
                    beforeEach {
                        input = "https://scans.example.com"
                        result = AppModel.baseURL(fromHostInput: input)
                    }

                    it("preserves it") {
                        expect(result?.absoluteString).to(equal("https://scans.example.com"))
                    }
                }

                context("when the input has surrounding whitespace and a port") {
                    beforeEach {
                        input = "  10.0.1.111:8080  "
                        result = AppModel.baseURL(fromHostInput: input)
                    }

                    it("trims the whitespace and keeps the port") {
                        expect(result?.absoluteString).to(equal("http://10.0.1.111:8080"))
                    }
                }

                context("when the input is blank") {
                    beforeEach {
                        input = "   "
                        result = AppModel.baseURL(fromHostInput: input)
                    }

                    it("returns nil") {
                        expect(result).to(beNil())
                    }
                }
            }

            // AppModel is @MainActor, so the specs below need Quick's async
            // DSL -- plain QuickSpec's `it` only accepts a synchronous
            // closure (Quick 7 gates async/await support behind the
            // AsyncSpec base class this file uses instead; see
            // Quick/Documentation/en-us/AsyncAwait.md). beforeEach/it hop to
            // the main actor via `await MainActor.run { ... }`, the pattern
            // that doc recommends for running synchronous, MainActor-bound
            // code from an otherwise-async example -- mirrors the
            // `@MainActor func test...()` isolation the old XCTest cases
            // used, just expressed as an explicit hop instead of a function
            // attribute.

            context("with a connected model showing one scan") {
                // beforeEach/it each hop onto the main actor independently
                // (see the comment above), so these two vars are written and
                // read from a series of separate `MainActor.run` closures
                // rather than one continuous isolated scope. Quick never
                // runs more than one of those closures at a time for a given
                // example -- beforeEach always finishes before its it
                // starts -- so there's no actual race, but the compiler has
                // no way to know that about a third-party library's
                // execution order. nonisolated(unsafe) says exactly that:
                // the isolation checker can't verify this is safe, but it is.
                nonisolated(unsafe) var model: AppModel!
                nonisolated(unsafe) var scan: ScanEntry!

                beforeEach {
                    await MainActor.run {
                        model = AppModel(defaults: makeEphemeralDefaults(), autoConnect: false)
                        scan = ScanEntry(
                            name: "1782420815.pdf",
                            size: 7,
                            time: "2026-06-25T10:30:00-07:00",
                            path: "/download/1782420815.pdf"
                        )
                        model.scans = [scan]
                    }
                }

                describe("#toggle(_:)") {
                    // Click-to-select / click-again-to-deselect, and that
                    // selectedScan looks the selected id back up in the
                    // current scan list.
                    it("selects then deselects the same scan") {
                        await MainActor.run {
                            model.toggle(scan)
                            expect(model.selectedScanID).to(equal(scan.id))
                            expect(model.selectedScan).to(equal(scan))

                            model.toggle(scan)
                            expect(model.selectedScanID).to(beNil())
                            expect(model.selectedScan).to(beNil())
                        }
                    }

                    context("with a savedMessage lingering from a previous open(_:)") {
                        // The footer can only show one thing at a time: a
                        // fresh selection should take over from a lingering
                        // "saved to Downloads" message, not show both.
                        beforeEach {
                            await MainActor.run {
                                model.savedMessage = "1782420815.pdf saved to Downloads."
                            }
                        }

                        it("clears the saved message on a fresh selection") {
                            await MainActor.run {
                                model.toggle(scan)
                                expect(model.savedMessage).to(beNil())
                                expect(model.selectedScanID).to(equal(scan.id))
                            }
                        }
                    }
                }

                describe("#changeServer()") {
                    it("clears the selection and the scan list") {
                        await MainActor.run {
                            model.toggle(scan)
                            model.changeServer()

                            expect(model.selectedScanID).to(beNil())
                            expect(model.scans).to(beEmpty())
                        }
                    }
                }
            }
        }
    }
}

private func makeEphemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "zouk.tests.\(UUID().uuidString)")!
}
