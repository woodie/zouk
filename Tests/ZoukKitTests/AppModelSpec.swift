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

            // AsyncSpec (not QuickSpec) is needed since AppModel is @MainActor.

            context("with a connected model showing one scan") {
                // nonisolated(unsafe): Quick serializes beforeEach/it so there's no real race, but the compiler can't see that.
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
                    context("when toggled once") {
                        beforeEach { await MainActor.run { model.toggle(scan) } }

                        it("selects the scan") {
                            await MainActor.run {
                                expect(model.selectedScanID).to(equal(scan.id))
                                expect(model.selectedScan).to(equal(scan))
                            }
                        }

                        context("when toggled again") {
                            beforeEach { await MainActor.run { model.toggle(scan) } }

                            it("deselects the scan") {
                                await MainActor.run {
                                    expect(model.selectedScanID).to(beNil())
                                    expect(model.selectedScan).to(beNil())
                                }
                            }
                        }
                    }

                    context("with a savedMessage lingering from a previous open(_:)") {
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
                    context("with a scan selected") {
                        beforeEach { await MainActor.run { model.toggle(scan) } }

                        it("clears the selection and the scan list") {
                            await MainActor.run {
                                model.changeServer()
                                expect(model.selectedScanID).to(beNil())
                                expect(model.scans).to(beEmpty())
                            }
                        }
                    }
                }

                describe("#requestDelete(_:)") {
                    // Only the footer trash button calls this; right-click "Move to Trash" skips confirmation entirely.
                    it("selects the scan and arms pendingDelete for it") {
                        await MainActor.run {
                            model.requestDelete(scan)

                            expect(model.selectedScanID).to(equal(scan.id))
                            expect(model.pendingDelete).to(equal(scan))
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
