import Foundation
import Quick
import Nimble
@testable import ZoukKit

final class ExtensionEnforcingPanelDelegateSpec: QuickSpec {
    override class func spec() {
        describe("ExtensionEnforcingPanelDelegate") {
            let delegate = ExtensionEnforcingPanelDelegate(requiredExtension: "pdf")

            describe("#panel(_:userEnteredFilename:confirmed:)") {
                var result: String?
                var entered: String!
                var confirmed: Bool!

                justBeforeEach { result = delegate.panel(NSObject(), userEnteredFilename: entered, confirmed: confirmed) }

                context("while the user is still typing (confirmed: false)") {
                    beforeEach { confirmed = false; entered = "name.zip"; }

                    it("leaves the filename unchanged") {
                        expect(result).to(equal(entered))
                    }
                }

                context("once confirmed (confirmed: true)") {
                    beforeEach { confirmed = true }

                    context("when the typed filename has a different extension") {
                        beforeEach { entered = "filename.zip" }

                        it("replaces it with the required extension instead of appending") {
                            expect(result).to(equal("filename.pdf"))
                        }
                    }

                    context("when the typed filename already has the required extension") {
                        beforeEach { entered = "filename.pdf" }

                        it("keeps it as a single extension") {
                            expect(result).to(equal("filename.pdf"))
                        }
                    }

                    context("when the typed filename has no extension at all") {
                        beforeEach { entered = "filename" }

                        it("appends the required extension") {
                            expect(result).to(equal("filename.pdf"))
                        }
                    }

                    context("when the typed filename is empty") {
                        beforeEach { entered = "" }

                        it("returns just the required extension") {
                            expect(result).to(equal(".pdf"))
                        }
                    }
                }
            }
        }
    }
}
