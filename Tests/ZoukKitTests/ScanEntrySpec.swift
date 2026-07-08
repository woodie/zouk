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

                    it("is non-nil and includes trailing \" ago\"") {
                        expect(scan.timeAgo(relativeTo: Date())).toNot(beNil())
                        expect(scan.timeAgo(relativeTo: Date())).to(endWith(" ago"))
                    }
                }

                context("with an unparsable timestamp") {
                    beforeEach { scan = ScanEntry(name: name, size: size, time: "invalid", path: path) }

                    it("is nil") {
                        expect(scan.timeAgo(relativeTo: Date())).to(beNil())
                    }
                }

                context("with files can be older/newer") {
                    let downloadedString = "2026-07-02T12:00:00Z"
                    let downloadedDate = ISO8601DateFormatter().date(from: downloadedString)!
                    var timeNow: Date!

                    beforeEach { scan = ScanEntry(name: name, size: size, time: downloadedString, path: path) }

                    context("just now") {
                        beforeEach { timeNow = downloadedDate }

                        it("displays less than a minute ago") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("less than a minute ago"))
                        }
                    }

                    context("three minutes ago") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(3 * 60) }

                        it("displays 3 minutes ago") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("3 minutes ago"))
                        }
                    }

                    context("fifteen hours ago") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(15 * 60 * 60) }

                        it("displays 15 hours ago") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("15 hours ago"))
                        }
                    }

                    context("thirty hours ago") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(30 * 60 * 60) }

                        it("displays 1 day ago") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("1 day ago"))
                        }
                    }

                    context("when files can be newer") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(-3 * 60) }

                        it("displays in the future") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("in 3 minutes"))
                        }
                    }
                }
            }
        }
    }
}
