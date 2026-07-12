import Foundation
import Humane

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
        Humane.SizeFormatter.humanSize(size)
    }

    public var formattedDate: String? {
        guard let downloadedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: downloadedAt)
    }

    // whenNil absorbs what used to be this method's own `guard let
    // downloadedAt else { return nil }` -- callers no longer need a `??`
    // fallback of their own (see ScanGridView). approximate: true is
    // humane-swift's default as of v0.9.0, so it's no longer passed
    // explicitly.
    public func timeAgo(relativeTo now: Date) -> String {
        Humane.TimeFormatter.timeAgo(downloadedAt, now, whenNil: "an unknown time")
    }
}
