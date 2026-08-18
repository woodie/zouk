import Foundation
import Quick
import Nimble
@testable import ZoukKit

// Guards the constants ZoukApp.swift's title/menu/About-panel text are built from.
final class AppInfoSpec: QuickSpec {
    override class func spec() {
        describe("AppInfo") {
            describe("shortName") {
                it("matches macOS's real app-menu (\"Hide Zouk\"/\"Quit Zouk\")") {
                    expect(AppInfo.shortName).to(equal("Zouk"))
                }
            }

            describe("fullName") {
                it("matches the window title and About panel's applicationName") {
                    expect(AppInfo.fullName).to(equal("Zouk scan retriever"))
                }

                it("is shortName plus \"scan retriever\", not an independent literal") {
                    expect(AppInfo.fullName).to(equal("\(AppInfo.shortName) scan retriever"))
                }
            }
        }
    }
}
