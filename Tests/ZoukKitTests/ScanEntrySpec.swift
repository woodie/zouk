import Foundation
import Quick
import Nimble
@testable import ZoukKit

final class ScanEntrySpec: QuickSpec {
    override class func spec() {
        describe("ScanEntry") {
            let name = "1779907271.pdf"
            let size = 500_000
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

            describe("#humanSize") {
                var scan: ScanEntry!
                beforeEach { scan = ScanEntry(name: name, size: size, time: time, path: path) }

                it("is human readable") {
                    expect(scan.humanSize).to(contain("500 KB"))
                }
            }

            describe("#timeAgo(relativeTo:)") {
                var scan: ScanEntry!

                context("with a valid timestamp") {
                    beforeEach { scan = ScanEntry(name: name, size: size, time: time, path: path) }

                    it("includes trailing \" ago\"") {
                        expect(scan.timeAgo(relativeTo: Date())).to(endWith(" ago"))
                    }
                }

                context("with an unparsable timestamp") {
                    beforeEach { scan = ScanEntry(name: name, size: size, time: "invalid", path: path) }

                    it("falls back to the whenNil text instead of requiring the caller to guard") {
                        expect(scan.timeAgo(relativeTo: Date())).to(equal("an unknown time"))
                    }
                }
            }
        }
    }
}
