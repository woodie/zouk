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

            context("constructed with a previously saved host") {
                it("reads hostInput back out of UserDefaults") {
                    let defaults = makeEphemeralDefaults()
                    defaults.set("scans.example.com", forKey: "zouk.lastHost")

                    let model = await MainActor.run {
                        AppModel(defaults: defaults, autoConnect: false, client: nil)
                    }

                    await MainActor.run {
                        expect(model.hostInput).to(equal("scans.example.com"))
                    }
                }
            }

            context("connect() with a blank hostInput") {
                it("fails without attempting a network call") {
                    let model = await MainActor.run {
                        AppModel(defaults: makeEphemeralDefaults(), autoConnect: false, client: nil)
                    }

                    await model.connect()

                    await MainActor.run {
                        expect(model.state).to(equal(
                            .failed("Enter a hostname or IP address, like scans.example.com or 10.0.1.111.")
                        ))
                        expect(model.hasEverConnected).to(beFalse())
                    }
                }
            }

            // Swift/Quick has no equivalent of kotlinx-coroutines-test's runTest virtual time
            // (see huck's own AppModelSpec.kt comment on this exact gap), so this context and
            // "connect() with a client that throws" below each pay a real ~2s
            // minimumConnectingDuration wait.
            context("connect() with a valid host and a client that succeeds") {
                it("stores the scans, marks hasEverConnected, and persists the host") {
                    let defaults = makeEphemeralDefaults()
                    let fixtureScan = ScanEntry(
                        name: "scan.pdf", size: 79_992, time: "2026-07-19T10:00:00Z", path: "/files/scan.pdf"
                    )
                    let fakeClient = FakeScanClient()
                    fakeClient.fetchScansHandler = { [fixtureScan] }
                    let model = await MainActor.run {
                        AppModel(
                            defaults: defaults, autoConnect: false, client: nil,
                            clientFactory: { _ in fakeClient }
                        )
                    }
                    await MainActor.run { model.hostInput = "scans.example.com" }

                    await model.connect()

                    await MainActor.run {
                        expect(model.state).to(equal(.connected))
                        expect(model.hasEverConnected).to(beTrue())
                        expect(model.scans).to(equal([fixtureScan]))
                    }
                    expect(defaults.string(forKey: "zouk.lastHost")).to(equal("scans.example.com"))
                }
            }

            context("connect() with a client that throws") {
                it("fails and leaves hasEverConnected false") {
                    let fakeClient = FakeScanClient()
                    fakeClient.fetchScansHandler = { throw URLError(.unknown) }
                    let model = await MainActor.run {
                        AppModel(
                            defaults: makeEphemeralDefaults(), autoConnect: false, client: nil,
                            clientFactory: { _ in fakeClient }
                        )
                    }
                    await MainActor.run { model.hostInput = "scans.example.com" }

                    await model.connect()

                    await MainActor.run {
                        expect(model.state).to(equal(.failed("Check that it's on the same network.")))
                        expect(model.hasEverConnected).to(beFalse())
                    }
                }
            }

            context("changeServer()") {
                it("resets hasEverConnected, state, and scans") {
                    let fixtureScan = ScanEntry(
                        name: "scan.pdf", size: 79_992, time: "2026-07-19T10:00:00Z", path: "/files/scan.pdf"
                    )
                    let fakeClient = FakeScanClient()
                    fakeClient.fetchScansHandler = { [fixtureScan] }
                    let model = await MainActor.run {
                        AppModel(
                            defaults: makeEphemeralDefaults(), autoConnect: false, client: nil,
                            clientFactory: { _ in fakeClient }
                        )
                    }
                    await MainActor.run { model.hostInput = "scans.example.com" }
                    await model.connect()

                    await MainActor.run {
                        model.changeServer()

                        expect(model.state).to(equal(.idle))
                        expect(model.hasEverConnected).to(beFalse())
                        expect(model.scans).to(beEmpty())
                    }
                }
            }

            // AsyncSpec (not QuickSpec) is needed since AppModel is @MainActor.

            context("with a connected model showing one scan") {
                // nonisolated(unsafe): Quick serializes beforeEach/it so there's no real race, but the compiler can't see that.
                nonisolated(unsafe) var model: AppModel!
                nonisolated(unsafe) var scan: ScanEntry!
                nonisolated(unsafe) var fakeClient: FakeScanClient!

                beforeEach {
                    await MainActor.run {
                        fakeClient = FakeScanClient()
                        model = AppModel(defaults: makeEphemeralDefaults(), autoConnect: false, client: fakeClient)
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

                describe("#delete(_:)") {
                    justBeforeEach { await model.delete(scan) }

                    context("when the server confirms the delete") {
                        beforeEach {
                            fakeClient.deleteHandler = { _ in }
                            await MainActor.run { model.selectedScanID = scan.id }
                        }

                        it("removes the scan from scans and clears the selection") {
                            await MainActor.run {
                                expect(model.scans).to(beEmpty())
                                expect(model.selectedScanID).to(beNil())
                            }
                        }
                    }

                    context("when the server rejects the delete") {
                        beforeEach {
                            fakeClient.deleteHandler = { _ in throw URLError(.unknown) }
                            await MainActor.run { model.state = .connected }
                        }

                        it("leaves scans and state untouched, and clears the failure flash afterward") {
                            await MainActor.run {
                                expect(model.scans).to(equal([scan]))
                                expect(model.state).to(equal(.connected))
                                expect(model.savingMessage).to(beNil())
                            }
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
