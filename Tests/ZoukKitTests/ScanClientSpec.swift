import Foundation
import Quick
import Nimble
@testable import ZoukKit

final class ScanClientSpec: AsyncSpec {
    override class func spec() {
        describe("ScanClient") {
            let name = "1779907271.pdf"
            let size = 7
            let time = "2026-06-25T10:30:00-07:00"
            let path = "/download/\(name)"

            let baseURL = URL(string: "http://scans.example.com")!
            let scan = ScanEntry(name: name, size: size, time: time, path: path)

            describe("#fetchScans()") {
                var fakeSession: FakeHTTPClient!
                var client: ScanClient!
                var clientBaseURL: URL!
                var request: URLRequest!

                func listing(_ files: [(name: String, modified: String)]) -> Data {
                    let responses = files.map { file in
                        """
                        <D:response><D:href>/\(file.name)</D:href><D:propstat><D:prop>
                        <D:displayname>\(file.name)</D:displayname><D:getcontentlength>7</D:getcontentlength>
                        <D:getlastmodified>\(file.modified)</D:getlastmodified><D:resourcetype/>
                        </D:prop></D:propstat></D:response>
                        """
                    }
                    let folder = "<D:response><D:href>/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>"
                    return Data("<D:multistatus xmlns:D=\"DAV:\">\(folder)\(responses.joined())</D:multistatus>".utf8)
                }

                beforeEach {
                    fakeSession = FakeHTTPClient()
                    clientBaseURL = baseURL
                }

                justBeforeEach { client = ScanClient(baseURL: clientBaseURL, session: fakeSession) }

                context("when the server responds with 207 and a WebDAV listing") {
                    var scans: [ScanEntry]!

                    beforeEach {
                        let body = listing([
                            (name: "older.pdf", modified: "Mon, 12 Oct 2026 21:48:35 GMT"),
                            (name: "newer.pdf", modified: "Tue, 13 Oct 2026 00:38:33 GMT")
                        ])
                        fakeSession.requestHandler = { sent in
                            request = sent
                            let response = HTTPURLResponse(url: sent.url!, statusCode: 207, httpVersion: nil, headerFields: nil)!
                            return (body, response)
                        }
                    }

                    justBeforeEach { scans = try await client.fetchScans() }

                    it("sends PROPFIND with Depth: 1 to the folder at baseURL") {
                        expect(request?.httpMethod).to(equal("PROPFIND"))
                        expect(request?.value(forHTTPHeaderField: "Depth")).to(equal("1"))
                        expect(request?.url?.absoluteString).to(equal("http://scans.example.com/"))
                    }

                    it("returns the files, newest first, without the folder itself") {
                        expect(scans.map(\.name)).to(equal(["newer.pdf", "older.pdf"]))
                    }

                    context("when baseURL has a path without a trailing slash") {
                        beforeEach { clientBaseURL = URL(string: "http://10.0.1.111:8081/scans")! }

                        it("adds the trailing slash, since a redirect would drop PROPFIND") {
                            expect(request?.url?.absoluteString).to(equal("http://10.0.1.111:8081/scans/"))
                        }
                    }
                }

                context("when the server responds with a non-2xx status") {
                    beforeEach {
                        fakeSession.requestHandler = { sent in
                            let response = HTTPURLResponse(url: sent.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                            return (Data(), response)
                        }
                    }

                    it("throws ScanClientError.server with that status code") {
                        await expect { try await client.fetchScans() }.to(throwError(ScanClientError.server(500)))
                    }
                }

                context("when the server only speaks the old files.json protocol") {
                    var scans: [ScanEntry]!
                    var legacyURL: URL!

                    beforeEach {
                        fakeSession.requestHandler = { sent in
                            let response = HTTPURLResponse(url: sent.url!, statusCode: 405, httpVersion: nil, headerFields: nil)!
                            return (Data(), response)
                        }
                        let body = try! JSONEncoder().encode([scan])
                        fakeSession.dataHandler = { url in
                            legacyURL = url
                            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                            return (body, response)
                        }
                    }

                    justBeforeEach { scans = try await client.fetchScans() }

                    it("falls back to files.json under baseURL") {
                        expect(legacyURL?.absoluteString).to(equal("http://scans.example.com/files.json"))
                    }

                    it("returns the scans files.json lists") {
                        expect(scans).to(equal([scan]))
                    }
                }

                context("when the server doesn't speak WebDAV") {
                    beforeEach {
                        fakeSession.requestHandler = { sent in
                            let response = HTTPURLResponse(url: sent.url!, statusCode: 405, httpVersion: nil, headerFields: nil)!
                            return (Data(), response)
                        }
                    }

                    it("throws ScanClientError.server(405) when files.json isn't there either") {
                        await expect { try await client.fetchScans() }.to(throwError(ScanClientError.server(405)))
                        expect(ScanClientError.server(405).errorDescription).to(contain("WebDAV"))
                    }
                }
            }

            describe("#cachedFile(for:in:)") {
                var fakeSession: FakeHTTPClient!
                var client: ScanClient!
                var cacheDirectory: URL!
                var local: URL!

                beforeEach {
                    fakeSession = FakeHTTPClient()
                    client = ScanClient(baseURL: baseURL, session: fakeSession)
                    cacheDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("zouk-tests-\(UUID().uuidString)", isDirectory: true)
                }

                afterEach {
                    try? FileManager.default.removeItem(at: cacheDirectory)
                }

                justBeforeEach { local = try await client.cachedFile(for: scan, in: cacheDirectory) }

                context("when the file isn't cached yet") {
                    let bytes = Data("pdf bytes".utf8)
                    var requestedURL: URL!

                    beforeEach {
                        fakeSession.downloadHandler = { url in
                            requestedURL = url
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                            try bytes.write(to: tempURL)
                            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                            return (tempURL, response)
                        }
                    }

                    it("downloads from scan.path resolved against baseURL") {
                        expect(requestedURL?.absoluteString).to(equal("http://scans.example.com/download/1779907271.pdf"))
                    }

                    it("saves the downloaded bytes under the scan's name in cacheDirectory") {
                        expect(local).to(equal(cacheDirectory.appendingPathComponent(scan.name)))
                        expect(FileManager.default.contents(atPath: local.path)).to(equal(bytes))
                    }
                }

                context("when the file is already cached and its size matches scan.size") {
                    // Matches scan.size (7) so cachedFile trusts the cache; see the mismatch context below.
                    let existingBytes = Data("is-here".utf8)

                    beforeEach {
                        try! FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                        try! existingBytes.write(to: cacheDirectory.appendingPathComponent(scan.name))
                        // Tripwire: a call here would throw and fail the test if the short-circuit logic ever regressed.
                        fakeSession.downloadHandler = { _ in throw URLError(.unknown) }
                    }

                    it("returns the already-cached file without downloading again") {
                        expect(FileManager.default.contents(atPath: local.path)).to(equal(existingBytes))
                    }
                }

                context("when a same-named file is cached but its size doesn't match scan.size") {
                    // Regression test for the stale-cache bug (ScanClient.cachedFile(for:in:)).
                    let staleBytes = Data("stale, wrong file entirely".utf8)
                    let freshBytes = Data("pdf bytes".utf8)
                    var requestedURL: URL!

                    beforeEach {
                        try! FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                        try! staleBytes.write(to: cacheDirectory.appendingPathComponent(scan.name))

                        fakeSession.downloadHandler = { url in
                            requestedURL = url
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                            try freshBytes.write(to: tempURL)
                            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                            return (tempURL, response)
                        }
                    }

                    it("re-downloads from scan.path instead of trusting the stale cache") {
                        expect(requestedURL?.absoluteString).to(equal("http://scans.example.com/download/1779907271.pdf"))
                    }

                    it("overwrites the cached file with the freshly downloaded bytes") {
                        expect(FileManager.default.contents(atPath: local.path)).to(equal(freshBytes))
                    }
                }
            }

            describe("#delete(_:)") {
                var fakeSession: FakeHTTPClient!
                var client: ScanClient!

                beforeEach {
                    fakeSession = FakeHTTPClient()
                    client = ScanClient(baseURL: baseURL, session: fakeSession)
                }

                context("when the server responds with 204") {
                    var requestedURL: URL!
                    var requestedMethod: String!

                    beforeEach {
                        fakeSession.requestHandler = { request in
                            requestedURL = request.url
                            requestedMethod = request.httpMethod
                            let response = HTTPURLResponse(
                                url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil
                            )!
                            return (Data(), response)
                        }
                        try await client.delete(scan)
                    }

                    it("sends DELETE to scan.path resolved against baseURL") {
                        expect(requestedURL?.absoluteString).to(equal("http://scans.example.com/download/1779907271.pdf"))
                        expect(requestedMethod).to(equal("DELETE"))
                    }
                }

                context("when the server responds with a non-2xx status") {
                    beforeEach {
                        fakeSession.requestHandler = { request in
                            let response = HTTPURLResponse(
                                url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil
                            )!
                            return (Data(), response)
                        }
                    }

                    it("throws ScanClientError.server with that status code") {
                        await expect { try await client.delete(scan) }.to(throwError(ScanClientError.server(404)))
                    }
                }
            }

            describe("#save(_:to:cacheDirectory:)") {
                var fakeSession: FakeHTTPClient!
                var client: ScanClient!
                var cacheDirectory: URL!
                var destination: URL!
                var saved: URL!
                let bytes = Data("pdf bytes".utf8)

                beforeEach {
                    fakeSession = FakeHTTPClient()
                    client = ScanClient(baseURL: baseURL, session: fakeSession)
                    let root = FileManager.default.temporaryDirectory
                        .appendingPathComponent("zouk-tests-\(UUID().uuidString)", isDirectory: true)
                    cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
                    destination = root.appendingPathComponent("Downloads", isDirectory: true)
                        .appendingPathComponent(scan.name)
                    try! FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                    )

                    fakeSession.downloadHandler = { url in
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                        try bytes.write(to: tempURL)
                        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                        return (tempURL, response)
                    }
                }
                afterEach { try? FileManager.default.removeItem(at: cacheDirectory.deletingLastPathComponent()) }

                justBeforeEach { saved = try await client.save(scan, to: destination, cacheDirectory: cacheDirectory) }

                context("when destination has no existing file") {
                    it("returns destination") {
                        expect(saved).to(equal(destination))
                    }

                    it("copies the cached scan's bytes to destination") {
                        expect(FileManager.default.contents(atPath: destination.path)).to(equal(bytes))
                    }
                }

                context("when destination already has a different file") {
                    beforeEach {
                        try! Data("stale".utf8).write(to: destination)
                    }

                    it("overwrites it with the cached scan's bytes") {
                        expect(FileManager.default.contents(atPath: destination.path)).to(equal(bytes))
                    }
                }
            }

            describe("#uniqueDestination(for:in:)") {
                var directory: URL!
                var destination: URL!

                beforeEach {
                    directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("zouk-tests-\(UUID().uuidString)", isDirectory: true)
                    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }

                afterEach { try? FileManager.default.removeItem(at: directory) }

                justBeforeEach { destination = ScanClient.uniqueDestination(for: "scan.pdf", in: directory) }

                context("when nothing exists at that name yet") {
                    it("returns the name unchanged") {
                        expect(destination).to(equal(directory.appendingPathComponent("scan.pdf")))
                    }
                }

                context("when \"scan.pdf\" already exists") {
                    beforeEach {
                        try! Data().write(to: directory.appendingPathComponent("scan.pdf"))
                    }

                    it("returns \"scan (1).pdf\"") {
                        expect(destination).to(equal(directory.appendingPathComponent("scan (1).pdf")))
                    }

                    context("and \"scan (1).pdf\" also already exists") {
                        beforeEach {
                            try! Data().write(to: directory.appendingPathComponent("scan (1).pdf"))
                        }

                        it("returns \"scan (2).pdf\"") {
                            expect(destination).to(equal(directory.appendingPathComponent("scan (2).pdf")))
                        }
                    }
                }
            }
        }
    }
}
