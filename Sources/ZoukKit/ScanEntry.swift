import Foundation

/// Mirrors one entry from scandalous's `/scans.json` stopgap endpoint
/// (see scandalous/docs/adr/0001-remote-family-access.md). `name` is a
/// server-generated Unix-timestamp filename like "1779907271.pdf" -- never
/// user input -- so it's safe to use directly as a local file/cache name
/// with no sanitization.
public struct ScanEntry: Codable, Identifiable, Equatable {
    public let name: String
    public let size: Int
    public let time: String
    public let url: String

    public init(name: String, size: Int, time: String, url: String) {
        self.name = name
        self.size = size
        self.time = time
        self.url = url
    }

    public var id: String { name }

    public var downloadedAt: Date? {
        ISO8601DateFormatter().date(from: time)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
