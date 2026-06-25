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
    @Published public var selected: Set<String> = []
    @Published public var isBusy = false

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
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("zouk/files", isDirectory: true)
        self.downloadsDirectory = downloadsDirectory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

        if autoConnect, !hostInput.isEmpty {
            Task { await connect() }
        }
    }

    public func connect() async {
        guard let baseURL = Self.baseURL(fromHostInput: hostInput) else {
            state = .failed("Enter a hostname or IP address, like scans.netpress.com or 10.0.1.111.")
            return
        }
        state = .connecting
        isBusy = true
        defer { isBusy = false }

        let client = ScanClient(baseURL: baseURL)
        self.client = client
        do {
            scans = try await client.fetchScans()
            defaults.set(hostInput, forKey: Self.hostKey)
            hasEverConnected = true
            state = .connected
        } catch {
            state = .failed("Can't reach \(hostInput). Check that it's on the same network and try again.")
        }
    }

    public func changeServer() {
        hasEverConnected = false
        state = .idle
        scans = []
        selected = []
        client = nil
        thumbnailCache.removeAll()
    }

    public func toggle(_ scan: ScanEntry) {
        if selected.contains(scan.id) {
            selected.remove(scan.id)
        } else {
            selected.insert(scan.id)
        }
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

    public func downloadSelected() async {
        guard let client, !selected.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }

        for scan in scans where selected.contains(scan.id) {
            do {
                _ = try await client.download(scan, to: downloadsDirectory, cacheDirectory: cacheDirectory)
                selected.remove(scan.id)
            } catch {
                state = .failed("Lost connection to \(hostInput) while downloading \(scan.name).")
                return
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
