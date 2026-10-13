import Foundation
import Quick
import Nimble
@testable import ZoukKit

final class WebDAVListingSpec: QuickSpec {
    override class func spec() {
        describe("WebDAVListing.entries(from:)") {
            var xml: String!
            var entries: [ScanEntry]!

            justBeforeEach { entries = try? WebDAVListing.entries(from: Data(xml.utf8)) }

            context("with the reply nginx gave on the Pi") {
                beforeEach {
                    xml = """
                    <?xml version="1.0" encoding="utf-8" ?>
                    <D:multistatus xmlns:D="DAV:">
                    <D:response>
                    <D:href>/scans/</D:href>
                    <D:propstat>
                    <D:prop>
                    <D:displayname>scans</D:displayname>
                    <D:getlastmodified>Tue, 13 Oct 2026 00:38:31 GMT</D:getlastmodified>
                    <D:resourcetype><D:collection/></D:resourcetype>
                    </D:prop>
                    <D:status>HTTP/1.1 200 OK</D:status>
                    </D:propstat>
                    </D:response>
                    <D:response>
                    <D:href>/scans/1791851911.pdf</D:href>
                    <D:propstat>
                    <D:prop>
                    <D:displayname>1791851911.pdf</D:displayname>
                    <D:getcontentlength>252184</D:getcontentlength>
                    <D:getlastmodified>Tue, 13 Oct 2026 00:38:33 GMT</D:getlastmodified>
                    <D:resourcetype></D:resourcetype>
                    </D:prop>
                    <D:status>HTTP/1.1 200 OK</D:status>
                    </D:propstat>
                    </D:response>
                    </D:multistatus>
                    """
                }

                it("skips the folder itself") {
                    expect(entries?.count).to(equal(1))
                }

                it("reads the file's name, size and address") {
                    expect(entries?.first?.name).to(equal("1791851911.pdf"))
                    expect(entries?.first?.size).to(equal(252_184))
                    expect(entries?.first?.path).to(equal("/scans/1791851911.pdf"))
                }

                it("keeps the modified date as ISO 8601") {
                    expect(entries?.first?.time).to(equal("2026-10-13T00:38:33Z"))
                }
            }

            context("with a different namespace prefix, a self-closing resourcetype and an encoded address") {
                beforeEach {
                    xml = """
                    <?xml version="1.0"?>
                    <d:multistatus xmlns:d="DAV:">
                    <d:response>
                    <d:href>/scan%20with%20spaces.pdf</d:href>
                    <d:propstat><d:prop>
                    <d:displayname>scan with spaces.pdf</d:displayname>
                    <d:getcontentlength>7</d:getcontentlength>
                    <d:getlastmodified>Mon, 12 Oct 2026 21:48:35 GMT</d:getlastmodified>
                    <d:resourcetype/>
                    </d:prop></d:propstat>
                    </d:response>
                    </d:multistatus>
                    """
                }

                it("uses the plain name for display and the encoded address for requests") {
                    expect(entries?.first?.name).to(equal("scan with spaces.pdf"))
                    expect(entries?.first?.path).to(equal("/scan%20with%20spaces.pdf"))
                }
            }

            context("when an entry has no displayname") {
                beforeEach {
                    xml = """
                    <D:multistatus xmlns:D="DAV:"><D:response>
                    <D:href>/scans/scan%20one.pdf</D:href>
                    <D:propstat><D:prop><D:getcontentlength>1</D:getcontentlength><D:resourcetype/></D:prop></D:propstat>
                    </D:response></D:multistatus>
                    """
                }

                it("takes the name from the address") {
                    expect(entries?.first?.name).to(equal("scan one.pdf"))
                }
            }

            context("when an entry's modified date can't be read") {
                beforeEach {
                    xml = """
                    <D:multistatus xmlns:D="DAV:"><D:response>
                    <D:href>/a.pdf</D:href>
                    <D:propstat><D:prop><D:getlastmodified>yesterday-ish</D:getlastmodified><D:resourcetype/></D:prop></D:propstat>
                    </D:response></D:multistatus>
                    """
                }

                it("leaves the time empty, so the entry has no date") {
                    expect(entries?.first?.time).to(equal(""))
                    expect(entries?.first?.downloadedAt).to(beNil())
                }
            }

            context("when the reply isn't XML") {
                beforeEach { xml = "<html><body>405 Not Allowed" }

                it("throws ScanClientError.invalidResponse") {
                    expect { try WebDAVListing.entries(from: Data(xml.utf8)) }.to(throwError(ScanClientError.invalidResponse))
                }
            }
        }
    }
}
