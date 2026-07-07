import Foundation
@testable import ZoukKit

// @unchecked Sendable: each test owns its own instance before handing it to one ScanClient actor.
final class FakeHTTPClient: ScanHTTPClient, @unchecked Sendable {
    var dataHandler: ((URL) throws -> (Data, URLResponse))?
    var downloadHandler: ((URL) throws -> (URL, URLResponse))?
    var requestHandler: ((URLRequest) throws -> (Data, URLResponse))?

    func data(from url: URL) async throws -> (Data, URLResponse) {
        guard let dataHandler else { throw URLError(.unknown) }
        return try dataHandler(url)
    }

    func download(from url: URL) async throws -> (URL, URLResponse) {
        guard let downloadHandler else { throw URLError(.unknown) }
        return try downloadHandler(url)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let requestHandler else { throw URLError(.unknown) }
        return try requestHandler(request)
    }
}
