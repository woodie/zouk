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

                    context("fifty-nine minutes ago") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(59 * 60) }

                        it("displays 59 minutes ago, no \"about\" below the hour") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("59 minutes ago"))
                        }
                    }

                    context("exactly one hour ago") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(60 * 60) }

                        it("displays about 1 hour ago, the \"about\" threshold is inclusive") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("about 1 hour ago"))
                        }
                    }

                    context("fifteen hours ago") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(15 * 60 * 60) }

                        it("displays about 15 hours ago") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("about 15 hours ago"))
                        }
                    }

                    context("thirty hours ago") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(30 * 60 * 60) }

                        it("displays about 1 day ago") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("about 1 day ago"))
                        }
                    }

                    context("when files can be newer, within the hour") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(-3 * 60) }

                        it("displays in 3 minutes, no \"about\" below the hour") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("in 3 minutes"))
                        }
                    }

                    context("when files can be newer, past the hour") {
                        beforeEach { timeNow = downloadedDate.addingTimeInterval(-3 * 60 * 60) }

                        it("displays in about 3 hours") {
                            expect(scan.timeAgo(relativeTo: timeNow)).to(equal("in about 3 hours"))
                        }
                    }
                }
            }
        }
    }
}
