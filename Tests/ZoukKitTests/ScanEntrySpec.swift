import Foundation
import Quick
import Nimble
@testable import ZoukKit

final class ScanEntrySpec: QuickSpec {
    override class func spec() {
        describe("ScanEntry") {
            describe("decoding from server JSON") {
                it("decodes the name, size, time, and url fields") {
                    let json = Data("""
                    [{"name":"1779907271.pdf","size":7,
                      "time":"2026-06-25T10:30:00-07:00",
                      "url":"/download/1779907271.pdf"}]
                    """.utf8)

                    let scans = try JSONDecoder().decode([ScanEntry].self, from: json)

                    expect(scans).to(haveCount(1))
                    expect(scans[0].name).to(equal("1779907271.pdf"))
                    expect(scans[0].size).to(equal(7))
                    expect(scans[0].url).to(equal("/download/1779907271.pdf"))
                    expect(scans[0].downloadedAt).toNot(beNil())
                }
            }

            describe("#formattedSize") {
                it("is human readable for a multi-megabyte file") {
                    let scan = ScanEntry(name: "a.pdf", size: 1_500_000,
                    time: "2026-06-25T10:30:00-07:00", url: "/download/a.pdf")
                    expect(scan.formattedSize).to(contain("MB"))
                }
            }

            describe("#formattedDate") {
                // formattedDate is locale/relative-day dependent (e.g. "Today
                // at 4:11 PM"), so don't pin down the exact string -- just
                // confirm it tracks downloadedAt's nil-ness rather than
                // crashing or always returning nil.

                context("with a valid timestamp") {
                    it("is non-nil") {
                        let scan = ScanEntry(name: "a.pdf", size: 7,
                        time: "2026-06-25T10:30:00-07:00", url: "/download/a.pdf")
                        expect(scan.formattedDate).toNot(beNil())
                    }
                }

                context("with an unparsable timestamp") {
                    it("is nil, along with downloadedAt") {
                        let scan = ScanEntry(name: "a.pdf", size: 7,
                        time: "not-a-date", url: "/download/a.pdf")
                        expect(scan.downloadedAt).to(beNil())
                        expect(scan.formattedDate).to(beNil())
                    }
                }
            }
        }
    }
}
