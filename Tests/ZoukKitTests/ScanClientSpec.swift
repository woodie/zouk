import Foundation
import Quick
import Nimble
@testable import ZoukKit

final class ScanClientSpec: QuickSpec {
    override class func spec() {
        describe("ScanClient") {
            describe("download path resolution") {
                // ScanClient resolves "/download/:filename" (an absolute
                // path) against baseURL for the actual GET. Pin down that
                // URL's relativeTo: resolution behaves the way the
                // implementation assumes -- an absolute path replaces the
                // base's whole path, it doesn't get appended to it.
                it("resolves an absolute path against baseURL, replacing the whole path") {
                    let base = URL(string: "http://scans.example.com")!
                    let resolved = URL(string: "/download/1779907271.pdf", relativeTo: base)?.absoluteURL
                    expect(resolved?.absoluteString).to(equal("http://scans.example.com/download/1779907271.pdf"))
                }
            }

            describe("scans.json URL") {
                it("appends to a host with a port") {
                    let base = URL(string: "http://10.0.1.111:8080")!
                    expect(base.appendingPathComponent("scans.json").absoluteString)
                        .to(equal("http://10.0.1.111:8080/scans.json"))
                }
            }
        }
    }
}
