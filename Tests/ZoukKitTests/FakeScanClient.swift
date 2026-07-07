import Foundation
@testable import ZoukKit

final class FakeScanClient: ScanFetching, @unchecked Sendable {
    var fetchScansHandler: (() throws -> [ScanEntry])?
    var cachedFileHandler: ((ScanEntry, URL) throws -> URL)?
    var saveHandler: ((ScanEntry, URL, URL) throws -> URL)?
    var deleteHandler: ((ScanEntry) throws -> Void)?

    func fetchScans() async throws -> [ScanEntry] {
        guard let fetchScansHandler else { throw URLError(.unknown) }
        return try fetchScansHandler()
    }

    func cachedFile(for scan: ScanEntry, in cacheDirectory: URL) async throws -> URL {
        guard let cachedFileHandler else { throw URLError(.unknown) }
        return try cachedFileHandler(scan, cacheDirectory)
    }

    func save(_ scan: ScanEntry, to destination: URL, cacheDirectory: URL) async throws -> URL {
        guard let saveHandler else { throw URLError(.unknown) }
        return try saveHandler(scan, destination, cacheDirectory)
    }

    func delete(_ scan: ScanEntry) async throws {
        guard let deleteHandler else { throw URLError(.unknown) }
        try deleteHandler(scan)
    }
}
