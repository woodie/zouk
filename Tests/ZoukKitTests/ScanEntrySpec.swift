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

            describe("#timeAgo(relativeTo:)") {
                var scan: ScanEntry!

                context("with a valid timestamp") {
                    beforeEach { scan = ScanEntry(name: name, size: size, time: time, path: path) }

                    it("is non-nil and doesn't include a trailing \" ago\"") {
                        expect(scan.timeAgo(relativeTo: Date())).toNot(beNil())
                        expect(scan.timeAgo(relativeTo: Date())).toNot(endWith(" ago"))
                    }
                }

                context("with an unparsable timestamp") {
                    beforeEach { scan = ScanEntry(name: name, size: size, time: "invalid", path: path) }

                    it("is nil") {
                        expect(scan.timeAgo(relativeTo: Date())).to(beNil())
                    }
                }

                context("with an entry downloaded on 2026-07-02") {
                    let downloadedString = "2026-07-02T12:00:00Z"
                    let downloadedDate = ISO8601DateFormatter().date(from: downloadedString)!
                    var timeNow: Date!

                    beforeEach { scan = ScanEntry(name: name, size: size, time: downloadedString, path: path) }

                    context("twenty seconds later") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(20) }

                        it("displays less than a minute") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("less than a minute"))
                        }
                    }

                    context("eighty seconds later") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(80) }

                        it("displays 1 minute") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("1 minute"))
                        }
                    }

                    context("one day later") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(86400) }

                        it("displays 1 day") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("1 day"))
                        }
                    }
                }
            }
        }
    }
}
