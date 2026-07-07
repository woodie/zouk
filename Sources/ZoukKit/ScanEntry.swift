import Foundation

// name: server-generated, assumed-unique timestamp filename. path: server-relative.
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

    public var formattedDate: String? {
        guard let downloadedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: downloadedAt)
    }

    // Matches lambada-web/scandalous's timeAgo wording for the delete-confirm dialog.
    public var timeAgo: String? {
        timeAgo(relativeTo: Date())
    }

    public func timeAgo(relativeTo now: Date) -> String? {
        guard let downloadedAt else { return nil }
        // Sub-30-second durations are clamped to "less than a minute", matching scandalous/lambada-web.
        if abs(now.timeIntervalSince(downloadedAt)) < 30 {
            return "less than a minute"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let formatted = formatter.localizedString(for: downloadedAt, relativeTo: now)
        // Strip trailing " ago" so callers control placement, matching lambada-web's template func.
        return formatted.hasSuffix(" ago") ? String(formatted.dropLast(4)) : formatted
    }
}
