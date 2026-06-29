import Foundation

public enum ScanClientError: Error, LocalizedError, Equatable {
    case invalidResponse
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server sent back something that wasn't a valid scan list."
        case .server(let code):
            return "The server responded with status \(code)."
        }
    }
}

/// Just the two URLSession calls ScanClient needs, as a protocol so tests
/// can inject a fake instead of hitting the real network (see
/// FakeHTTPClient in ZoukKitTests).
public protocol ScanHTTPClient: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
    func download(from url: URL) async throws -> (URL, URLResponse)
}

extension URLSession: ScanHTTPClient {
    // URLSession's own data(from:)/download(from:) take a trailing
    // `delegate:` parameter with a default value -- a default value doesn't
    // make a method's signature match a protocol requirement that omits
    // the parameter outright, so these forward explicitly instead of
    // conforming "for free".
    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(from: url, delegate: nil)
    }

    public func download(from url: URL) async throws -> (URL, URLResponse) {
        try await download(from: url, delegate: nil)
    }
}

/// Talks to lambada-web's (or scandalous's) HTTP API: GET /files.json for
/// the listing, GET /download/:filename for the bytes. Downloaded files are cached on
/// disk by name (server-generated, supposedly immutable and never reused --
/// see ScanEntry) so a file fetched once to build a thumbnail is never
/// fetched twice when the user then clicks Download. `cachedFile(for:in:)`
/// double-checks that assumption against `scan.size` rather than trusting
/// it blindly -- see that method's doc comment.
public actor ScanClient {
    public let baseURL: URL
    private let session: any ScanHTTPClient

    /// `session` defaults to `.shared` for real use; tests inject a fake
    /// ScanHTTPClient (see FakeHTTPClient in ZoukKitTests) so
    /// `fetchScans()`/`cachedFile(for:in:)` can be called directly without
    /// touching the real network.
    public init(baseURL: URL, session: any ScanHTTPClient = URLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchScans() async throws -> [ScanEntry] {
        let listURL = baseURL.appendingPathComponent("files.json")
        let (data, response) = try await session.data(from: listURL)
        try Self.checkOK(response)
        return try JSONDecoder().decode([ScanEntry].self, from: data)
    }

    /// Returns a local file URL for `scan`, downloading into `cacheDirectory`
    /// only if it isn't already there *and matching `scan.size`*.
    ///
    /// The cache is keyed purely by `scan.name`, on the assumption
    /// (documented on `ScanEntry`) that the server never reuses a name.
    /// That assumption isn't actually enforced anywhere -- a server bug,
    /// or a name collision from outside zouk entirely (as happened during
    /// testing: a same-named file dropped directly into the server's
    /// directory), would otherwise make this silently and permanently
    /// serve the *old* file's bytes under the new entry's name, with
    /// nothing on screen to suggest anything's wrong beyond a thumbnail
    /// that looks like the wrong file. Comparing the cached file's actual
    /// size on disk to the size the server just reported for this name
    /// catches that case and re-downloads instead of trusting stale
    /// bytes. It's not foolproof (two genuinely different files could
    /// happen to be the same size), but the listing API doesn't give us
    /// anything stronger than size/time to check against, and this is
    /// already a strict improvement over no check at all.
    @discardableResult
    public func cachedFile(for scan: ScanEntry, in cacheDirectory: URL) async throws -> URL {
        let local = cacheDirectory.appendingPathComponent(scan.name)
        if FileManager.default.fileExists(atPath: local.path), Self.cachedSizeMatches(scan, at: local) {
            return local
        }
        guard let remote = URL(string: scan.path, relativeTo: baseURL) else {
            throw ScanClientError.invalidResponse
        }
        let (tempURL, response) = try await session.download(from: remote)
        try Self.checkOK(response)

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: local.path) {
            try FileManager.default.removeItem(at: local)
        }
        try FileManager.default.moveItem(at: tempURL, to: local)
        return local
    }

    /// Copies the (possibly already-cached) file straight to
    /// `destination`, whatever name and folder the caller chose for it --
    /// in practice, an NSSavePanel the caller already ran. No Finder-style
    /// de-dup naming here: the panel already resolved any "replace this
    /// file?" question before this is ever called, so this just writes
    /// to exactly the URL it's given.
    @discardableResult
    public func save(_ scan: ScanEntry, to destination: URL, cacheDirectory: URL) async throws -> URL {
        let cached = try await cachedFile(for: scan, in: cacheDirectory)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: cached, to: destination)
        return destination
    }

    private static func checkOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ScanClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ScanClientError.server(http.statusCode) }
    }

    /// Whether the file already sitting at `local` is plausibly still
    /// *this* scan's bytes, not a leftover from some earlier, unrelated
    /// file that happened to land under the same name. Unreadable
    /// attributes count as a mismatch -- safer to re-download than to
    /// serve a file we can't even confirm the size of.
    private static func cachedSizeMatches(_ scan: ScanEntry, at local: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: local.path),
              let cachedSize = attributes[.size] as? Int
        else { return false }
        return cachedSize == scan.size
    }
}
