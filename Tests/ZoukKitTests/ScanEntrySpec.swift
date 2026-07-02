import Foundation
import Quick
import Nimble
@testable import ZoukKit

final class ScanEntrySpec: QuickSpec {
    override class func spec() {
        describe("ScanEntry") {
            let name = "1779907271.pdf"
            let size = 1_500_000
            let time = "2026-06-25T10:30:00-07:00"
            let path = "/download/\(name)"

            describe("Decodable") {
                var scans: [ScanEntry]!

                context("when decoding a server JSON listing") {
                    beforeEach {
                        let json = Data("""
                        [{"name":"\(name)","size":\(size),"time":"\(time)","path":"\(path)"}]
                        """.utf8)
                        scans = try JSONDecoder().decode([ScanEntry].self, from: json)
                    }

                    it("decodes the name, size, time, and path fields") {
                        expect(scans).to(haveCount(1))
                        expect(scans[0].name).to(equal(name))
                        expect(scans[0].size).to(equal(size))
                        expect(scans[0].path).to(equal(path))
                        expect(scans[0].downloadedAt).toNot(beNil())
                    }
                }
            }

            describe("#formattedSize") {
                var scan: ScanEntry!
                beforeEach { scan = ScanEntry(name: name, size: size, time: time, path: path) }

                it("is human readable for a multi-megabyte file") {
                    expect(scan.formattedSize).to(contain("MB"))
                }
            }

            describe("#downloadedAt and #formattedDate") {
                var scan: ScanEntry!

                context("with a valid timestamp") {
                    beforeEach { scan = ScanEntry(name: name, size: size, time: time, path: path) }

                    it("are both non-nil") {
                        expect(scan.downloadedAt).toNot(beNil())
                        expect(scan.formattedDate).toNot(beNil())
                    }
                }

                context("with an unparsable timestamp") {
                    beforeEach { scan = ScanEntry(name: name, size: size, time: "invalid", path: path) }

                    it("are both nil") {
                        expect(scan.downloadedAt).to(beNil())
                        expect(scan.formattedDate).to(beNil())
                    }
                }
            }

            describe("#timeAgo") {
                var scan: ScanEntry!

                context("with a valid timestamp") {
                    beforeEach { scan = ScanEntry(name: name, size: size, time: time, path: path) }

                    it("is non-nil and doesn't include a trailing \" ago\"") {
                        // The delete confirmation dialog (ScanGridView) appends
                        // " ago?" itself -- matching lambada-web/scandalous's
                        // timeAgo template func, which returns just the
                        // duration for the same reason.
                        expect(scan.timeAgo).toNot(beNil())
                        expect(scan.timeAgo).toNot(endWith(" ago"))
                    }
                }

                context("with an unparsable timestamp") {
                    beforeEach { scan = ScanEntry(name: name, size: size, time: "invalid", path: path) }

                    it("is nil") {
                        expect(scan.timeAgo).to(beNil())
                    }
                }
            }

            describe("#timeAgo(relativeTo:)") {
                // Regression spec for the bug woodie caught 2026-07-02: deleting
                // a scan seconds after it arrived showed "Delete this scan from
                // 15 seconds ago" in zouk, while scandalous/lambada-web both
                // showed "less than a minute ago" for the same age -- see
                // docs/COWORK.md. Deterministic (fixed `now` passed in) rather
                // than depending on the real clock, unlike the #timeAgo spec
                // above.
                let downloadedAtString = "2026-07-02T12:00:00Z"
                var scan: ScanEntry!
                var downloadedAt: Date!

                beforeEach {
                    scan = ScanEntry(name: name, size: size, time: downloadedAtString, path: path)
                    downloadedAt = ISO8601DateFormatter().date(from: downloadedAtString)
                }

                it("clamps sub-30-second ages to \"less than a minute\", matching scandalous/lambada-web") {
                    let fifteenSecondsLater = downloadedAt.addingTimeInterval(15)
                    expect(scan.timeAgo(relativeTo: fifteenSecondsLater)).to(equal("less than a minute"))
                }

                it("still clamps right at the 29-second boundary") {
                    let twentyNineSecondsLater = downloadedAt.addingTimeInterval(29)
                    expect(scan.timeAgo(relativeTo: twentyNineSecondsLater)).to(equal("less than a minute"))
                }

                it("no longer clamps once 30 seconds have passed") {
                    let thirtySecondsLater = downloadedAt.addingTimeInterval(30)
                    expect(scan.timeAgo(relativeTo: thirtySecondsLater)).toNot(equal("less than a minute"))
                }
            }
        }
    }
}
