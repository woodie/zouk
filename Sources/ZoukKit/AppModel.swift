import AppKit
import Foundation
import PDFKit

public enum ConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)

    public var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Drives the whole app: remembers the last host the user typed in, opens
/// the host-entry screen until a connection succeeds, then holds the scan
/// listing and handles thumbnailing/downloading.
@MainActor
public final class AppModel: ObservableObject {
    @Published public var hostInput: String
    @Published public var state: ConnectionState = .idle
    @Published public private(set) var hasEverConnected = false
    @Published public var scans: [ScanEntry] = []
    /// The single scan currently highlighted by a click (Finder-style:
    /// click to select and show details, double-click to download).
    @Published public var selectedScanID: String?
    @Published public var isBusy = false
    /// Brief confirmation text (e.g. "Downloaded 2 files to Downloads.")
    /// shown after an action completes, so a click has visible proof it
    /// did something instead of just silently clearing the selection.
    @Published public var statusMessage: String?

    private static let hostKey = "zouk.lastHost"

    private let defaults: UserDefaults
    private let cacheDirectory: URL
    private let downloadsDirectory: URL
    private var client: ScanClient?
    private var thumbnailCache: [String: NSImage] = [:]

    public init(
        defaults: UserDefaults = .standard,
        cacheDirectory: URL? = nil,
        downloadsDirectory: URL? = nil,
        autoConnect: Bool = true
    ) {
        self.defaults = defaults
        self.hostInput = defaults.string(forKey: Self.hostKey) ?? ""
        self.cacheDirectory = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("zouk/files", isDirectory: true)
        self.downloadsDirectory = downloadsDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

        if autoConnect, !hostInput.isEmpty {
            Task { await connect() }
        }
    }

    /// ConnectingView (the running-dog screen) stays up at least this long
    /// once we've started attempting a connection, even if the network
    /// round-trip itself finishes much faster -- reconnecting to a saved
    /// host over a local network can resolve in a handful of milliseconds,
    /// which would otherwise skip right past it. Real, slower connections
    /// just take however long they take; this only ever adds time, never
    /// caps it.
    private static let minimumConnectingDuration: Duration = .seconds(2)

    public func connect() async {
        guard let baseURL = Self.baseURL(fromHostInput: hostInput) else {
            hasEverConnected = false
            state = .failed("Enter a hostname or IP address, like scans.example.com or 10.0.1.111.")
            return
        }
        state = .connecting
        isBusy = true
        defer { isBusy = false }

        let attemptStart = ContinuousClock.now
        let client = ScanClient(baseURL: baseURL)
        self.client = client
        do {
            scans = try await client.fetchScans()
            await Self.waitOutMinimumConnectingDuration(since: attemptStart)
            defaults.set(hostInput, forKey: Self.hostKey)
            hasEverConnected = true
            state = .connected
        } catch {
            await Self.waitOutMinimumConnectingDuration(since: attemptStart)
            // Any failure to connect -- whether this is the very first
            // attempt or a reload from an already-open grid -- just bounces
            // back to HostEntryView rather than showing an error in place,
            // so there's only ever one "something's wrong" screen.
            hasEverConnected = false
            state = .failed("Check that it's on the same network.")
        }
    }

    private static func waitOutMinimumConnectingDuration(since start: ContinuousClock.Instant) async {
        let elapsed = ContinuousClock.now - start
        guard elapsed < minimumConnectingDuration else { return }
        try? await Task.sleep(for: minimumConnectingDuration - elapsed)
    }

    public func changeServer() {
        hasEverConnected = false
        state = .idle
        scans = []
        selectedScanID = nil
        client = nil
        thumbnailCache.removeAll()
    }

    public var selectedScan: ScanEntry? {
        guard let selectedScanID else { return nil }
        return scans.first { $0.id == selectedScanID }
    }

    /// Single click: select/deselect for the info footer. Clicking the
    /// already-selected scan again deselects it.
    public func toggle(_ scan: ScanEntry) {
        selectedScanID = (selectedScanID == scan.id) ? nil : scan.id
    }

    public func thumbnail(for scan: ScanEntry) async -> NSImage? {
        if let cached = thumbnailCache[scan.id] { return cached }
        guard let client else { return nil }
        do {
            let fileURL = try await client.cachedFile(for: scan, in: cacheDirectory)
            guard let document = PDFDocument(url: fileURL), let page = document.page(at: 0) else { return nil }
            let image = page.thumbnail(of: CGSize(width: 160, height: 200), for: .cropBox)
            thumbnailCache[scan.id] = image
            return image
        } catch {
            return nil
        }
    }

    /// Double-click on a thumbnail: download just that one scan. The
    /// destination filename comes back from ScanClient, which appends
    /// " (1)", " (2)", etc. (Finder-style) if it's already in Downloads,
    /// so the confirmation message always names the file that actually
    /// landed on disk.
    public func download(_ scan: ScanEntry) async {
        guard let client else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let destination = try await client.download(scan, to: downloadsDirectory, cacheDirectory: cacheDirectory)
            showStatus("Downloaded \(destination.lastPathComponent) to Downloads.")
        } catch {
            state = .failed("Lost connection to \(hostInput) while downloading \(scan.name).")
        }
    }

    /// Shows `message` and clears it again after a few seconds, unless a
    /// newer status has already replaced it.
    private func showStatus(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(1))
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    /// Pure, nonisolated so it's easy to unit test: prepends "http://" when
    /// the user didn't type a scheme, trims whitespace, rejects empty input.
    public nonisolated static func baseURL(fromHostInput input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        return URL(string: withScheme)
    }
}
