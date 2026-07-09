import Foundation

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

    public var humanSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    public var formattedDate: String? {
        guard let downloadedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: downloadedAt)
    }

    // Emulate github.com/woodie/humane NewTimeFormatter CollapseMinute
    public func timeAgo(relativeTo now: Date) -> String? {
        guard let downloadedAt else { return nil }
        if abs(now.timeIntervalSince(downloadedAt)) < 30 {
            return "less than a minute ago"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: downloadedAt, relativeTo: now)
    }
}
