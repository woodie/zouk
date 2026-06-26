import Foundation

public enum ScanClientError: Error, LocalizedError {
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

/// Talks to scandalous's stopgap HTTP API: GET /scans.json for the listing,
/// GET /download/:filename for the bytes. Downloaded files are cached on
/// disk by name (server-generated, immutable, never reused -- see
/// ScanEntry) so a file fetched once to build a thumbnail is never fetched
/// twice when the user then clicks Download.
public actor ScanClient {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public func fetchScans() async throws -> [ScanEntry] {
        let listURL = baseURL.appendingPathComponent("scans.json")
        let (data, response) = try await URLSession.shared.data(from: listURL)
        try Self.checkOK(response)
        return try JSONDecoder().decode([ScanEntry].self, from: data)
    }

    /// Returns a local file URL for `scan`, downloading into `cacheDirectory`
    /// only if it isn't already there.
    @discardableResult
    public func cachedFile(for scan: ScanEntry, in cacheDirectory: URL) async throws -> URL {
        let local = cacheDirectory.appendingPathComponent(scan.name)
        if FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        guard let remote = URL(string: scan.url, relativeTo: baseURL) else {
            throw ScanClientError.invalidResponse
        }
        let (tempURL, response) = try await URLSession.shared.download(from: remote)
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
}
