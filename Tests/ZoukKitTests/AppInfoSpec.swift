import Foundation
import Quick
import Nimble
@testable import ZoukKit

// Guards ZoukApp.swift's three name usages (WindowGroup title, About menu item, About panel's
// applicationName) via the shared constants they're built from -- ZoukApp.swift itself lives in
// the "zouk" executable target and isn't reachable from this test target at all (see
// Package.swift's own comment, and AppInfo.swift's). huck's equivalent (AppInfoSpec.kt) doesn't
// need that indirection: its Main.kt is directly visible to its own test source set.
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
