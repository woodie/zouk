import Foundation
@testable import ZoukKit

/// Fake ScanHTTPClient for ScanClientSpec -- lets tests call fetchScans()/
/// cachedFile(for:in:) directly without touching the real network. Set
/// dataHandler/downloadHandler per test; an unset handler throws, same as a
/// real network failure would.
///
/// @unchecked Sendable: each test builds and configures its own instance
/// before handing it to a single ScanClient actor, so there's no shared
/// mutable state across concurrency domains in practice.
final class FakeHTTPClient: ScanHTTPClient, @unchecked Sendable {
    var dataHandler: ((URL) throws -> (Data, URLResponse))?
    var downloadHandler: ((URL) throws -> (URL, URLResponse))?

    func data(from url: URL) async throws -> (Data, URLResponse) {
        guard let dataHandler else { throw URLError(.unknown) }
        return try dataHandler(url)
    }

    func download(from url: URL) async throws -> (URL, URLResponse) {
        guard let downloadHandler else { throw URLError(.unknown) }
        return try downloadHandler(url)
    }
}
