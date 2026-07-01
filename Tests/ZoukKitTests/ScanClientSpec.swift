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

                beforeEach {
                    fakeSession = FakeHTTPClient()
                    client = ScanClient(baseURL: baseURL, session: fakeSession)
                }

                context("when the server responds with 200 and a valid listing") {
                    var scans: [ScanEntry]!
                    var requestedURL: URL!

                    beforeEach {
                        let body = try! JSONEncoder().encode([scan])
                        fakeSession.dataHandler = { url in
                            requestedURL = url
                            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                            return (body, response)
                        }
                        scans = try await client.fetchScans()
                    }

                    it("requests files.json under baseURL") {
                        expect(requestedURL?.absoluteString).to(equal("http://scans.example.com/files.json"))
                    }

                    it("decodes the scans the server returns") {
                        expect(scans).to(equal([scan]))
                    }
                }

                context("when the server responds with a non-2xx status") {
                    beforeEach {
                        fakeSession.dataHandler = { url in
                            let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
                            return (Data(), response)
                        }
                    }

                    it("throws ScanClientError.server with that status code") {
                        await expect { try await client.fetchScans() }.to(throwError(ScanClientError.server(500)))
                    }
                }
            }

            describe("#cachedFile(for:in:)") {
                var fakeSession: FakeHTTPClient!
                var client: ScanClient!
                var cacheDirectory: URL!

                beforeEach {
                    fakeSession = FakeHTTPClient()
                    client = ScanClient(baseURL: baseURL, session: fakeSession)
                    cacheDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("zouk-tests-\(UUID().uuidString)", isDirectory: true)
                }

                afterEach {
                    try? FileManager.default.removeItem(at: cacheDirectory)
                }

                context("when the file isn't cached yet") {
                    let bytes = Data("pdf bytes".utf8)
                    var requestedURL: URL!
                    var local: URL!

                    beforeEach {
                        fakeSession.downloadHandler = { url in
                            requestedURL = url
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                            try bytes.write(to: tempURL)
                            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                            return (tempURL, response)
                        }
                        local = try await client.cachedFile(for: scan, in: cacheDirectory)
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
                    // Exactly scan.size (7) bytes -- cachedFile compares
                    // against that before trusting the cache; see the
                    // mismatch context below for what happens when it
                    // doesn't match.
                    let existingBytes = Data("is-here".utf8)
                    var local: URL!

                    beforeEach {
                        try! FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                        try! existingBytes.write(to: cacheDirectory.appendingPathComponent(scan.name))
                        // Tripwire: if cachedFile ever stopped short-circuiting
                        // on an existing file, this handler being called would
                        // throw and fail the test below instead of silently
                        // passing for the wrong reason.
                        fakeSession.downloadHandler = { _ in throw URLError(.unknown) }

                        local = try await client.cachedFile(for: scan, in: cacheDirectory)
                    }

                    it("returns the already-cached file without downloading again") {
                        expect(FileManager.default.contents(atPath: local.path)).to(equal(existingBytes))
                    }
                }

                context("when a same-named file is cached but its size doesn't match scan.size") {
                    // Regression test: a file landing under a name that's
                    // already in zouk's local cache (whether from a server
                    // bug or, as found during manual testing, someone
                    // dropping a same-named file directly into the server's
                    // directory) used to be served from the stale cache
                    // forever -- e.g. a grid cell silently showing the old
                    // file's thumbnail for the new entry. cachedFile now
                    // notices the size mismatch and re-downloads instead.
                    let staleBytes = Data("stale, wrong file entirely".utf8)
                    let freshBytes = Data("pdf bytes".utf8)
                    var requestedURL: URL!
                    var local: URL!

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

                        local = try await client.cachedFile(for: scan, in: cacheDirectory)
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

                context("when destination has no existing file") {
                    var saved: URL!
                    beforeEach { saved = try await client.save(scan, to: destination, cacheDirectory: cacheDirectory) }

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
                        _ = try await client.save(scan, to: destination, cacheDirectory: cacheDirectory)
                    }

                    it("overwrites it with the cached scan's bytes") {
                        expect(FileManager.default.contents(atPath: destination.path)).to(equal(bytes))
                    }
                }
            }
        }
    }
}
