import Foundation

/// Mirrors one entry from the `/files.json` endpoint served by lambada-web
/// (or scandalous, its Ruby predecessor). `name` is a server-generated Unix-timestamp filename like
/// "1779907271.pdf" -- never user input -- so it's safe to use directly as
/// a local file/cache name with no sanitization. `path` is a
/// server-relative download path (e.g. "/download/1779907271.pdf"), not a
/// URL -- it was misnamed `url` until this field (and the endpoint itself,
/// previously `/scans.json`) were renamed for accuracy.
public struct ScanEntry: Codable, Identifiable, Equatable {
    public let name: String
    public let size: Int
    public let time: String
    public let path: String

    public init(name: String, size: Int, time: String, path: String) {
        self.name = name
        self.size = size
        self.time = time
        self.path = path
    }

    public var id: String { name }

    public var downloadedAt: Date? {
        ISO8601DateFormatter().date(from: time)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Finder-style relative timestamp ("Today at 4:11 PM", "Yesterday at
    /// 9:02 AM", or a plain date once it's further back) instead of a bare
    /// calendar date -- matches how Finder's list view shows Date Modified.
    public var formattedDate: String? {
        guard let downloadedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: downloadedAt)
    }
}
