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

    /// "6 days ago"/"less than a minute ago"-style relative age, without the
    /// "ago" suffix -- matches lambada-web/scandalous's own timeAgo/
    /// time_ago_in_words wording (both ultimately Rails' distance_of_time_in_words),
    /// used so the delete confirmation dialog (ScanGridView) reads the same
    /// way the web listing's own delete confirm does: "Delete this scan
    /// from <timeAgo> ago?". Uses the real current time -- see
    /// `timeAgo(relativeTo:)` for a version tests can pin to a fixed clock.
    public var timeAgo: String? {
        timeAgo(relativeTo: Date())
    }

    /// Same as `timeAgo`, but takes an explicit "now" instead of reading
    /// the real clock, so a test can assert exact wording (e.g. "15
    /// seconds before now" -> "less than a minute") deterministically.
    public func timeAgo(relativeTo now: Date) -> String? {
        guard let downloadedAt else { return nil }
        // Sub-30-second durations are clamped to "less than a minute", matching scandalous/lambada-web.
        if abs(now.timeIntervalSince(downloadedAt)) < 30 {
            return "less than a minute"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let formatted = formatter.localizedString(for: downloadedAt, relativeTo: now)
        // RelativeDateTimeFormatter includes its own "ago"/"in" -- strip a
        // trailing " ago" so callers control where that word goes, the same
        // way lambada-web's timeAgo template func returns just the
        // duration and the template appends " ago" itself.
        return formatted.hasSuffix(" ago") ? String(formatted.dropLast(4)) : formatted
    }
}
