import Foundation

public enum ScanClientError: Error, LocalizedError, Equatable {
    case invalidResponse
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server sent back something that wasn't a valid scan list."
        case .server(405):
            return "The server doesn't offer a WebDAV listing at that address (status 405)."
        case .server(let code):
            return "The server responded with status \(code)."
        }
    }
}

public protocol ScanHTTPClient: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
    func download(from url: URL) async throws -> (URL, URLResponse)
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: ScanHTTPClient {
    // Forwards explicitly; a default delegate: param doesn't satisfy the protocol requirement.
    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(from: url, delegate: nil)
    }

    public func download(from url: URL) async throws -> (URL, URLResponse) {
        try await download(from: url, delegate: nil)
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

public actor ScanClient {
    public let baseURL: URL
    private let session: any ScanHTTPClient

    public init(baseURL: URL, session: any ScanHTTPClient = URLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchScans() async throws -> [ScanEntry] {
        var request = URLRequest(url: Self.folderURL(baseURL))
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        let (data, response) = try await session.data(for: request)
        try Self.checkOK(response)
        return try WebDAVListing.entries(from: data).sorted {
            ($0.downloadedAt ?? .distantPast) > ($1.downloadedAt ?? .distantPast)
        }
    }

    // A folder URL without its trailing slash gets a redirect, which turns PROPFIND into GET.
    nonisolated static func folderURL(_ url: URL) -> URL {
        let absolute = url.absoluteString
        return absolute.hasSuffix("/") ? url : URL(string: absolute + "/") ?? url
    }

    // Re-downloads on a scan.size mismatch instead of trusting a stale same-named cache entry.
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

    @discardableResult
    public func save(_ scan: ScanEntry, to destination: URL, cacheDirectory: URL) async throws -> URL {
        let cached = try await cachedFile(for: scan, in: cacheDirectory)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: cached, to: destination)
        return destination
    }

    // DELETE on the file's own WebDAV address, the same one GET downloads from.
    public func delete(_ scan: ScanEntry) async throws {
        guard let remote = URL(string: scan.path, relativeTo: baseURL) else {
            throw ScanClientError.invalidResponse
        }
        var request = URLRequest(url: remote)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        try Self.checkOK(response)
    }

    // Finder-style de-dup naming: "scan.pdf" -> "scan (1).pdf" instead of overwriting.
    nonisolated static func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let fileExtension = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffixed = fileExtension.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(fileExtension)"
            candidate = directory.appendingPathComponent(suffixed)
            counter += 1
        }
        return candidate
    }

    private static func checkOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ScanClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ScanClientError.server(http.statusCode) }
    }

    // Unreadable attributes count as a mismatch; safer to re-download.
    private static func cachedSizeMatches(_ scan: ScanEntry, at local: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: local.path),
              let cachedSize = attributes[.size] as? Int
        else { return false }
        return cachedSize == scan.size
    }
}
