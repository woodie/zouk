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

@MainActor
public final class AppModel: ObservableObject {
    @Published public var hostInput: String
    @Published public var state: ConnectionState = .idle
    @Published public private(set) var hasEverConnected = false
    @Published public var scans: [ScanEntry] = []
    @Published public var selectedScanID: String?
    @Published public var isBusy = false
    // Also reused by delete(_:) for a "Couldn't delete ..." flash.
    @Published public var savingMessage: String?
    // Persistent (no auto-clear timer) so it isn't missed.
    @Published public var savedMessage: String?
    @Published public var pendingDelete: ScanEntry?

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

    // Floor, not a cap, so ConnectingView doesn't flash by on a fast local reconnect.
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
        savedMessage = nil
        client = nil
        thumbnailCache.removeAll()
    }

    public var selectedScan: ScanEntry? {
        guard let selectedScanID else { return nil }
        return scans.first { $0.id == selectedScanID }
    }

    public func toggle(_ scan: ScanEntry) {
        savedMessage = nil
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

    public func open(_ scan: ScanEntry) async {
        await saveViaPanel(scan, thenOpen: true)
    }

    public func downloadWithoutOpening(_ scan: ScanEntry) async {
        await saveViaPanel(scan, thenOpen: false)
    }

    // No Save panel here, so de-dup via ScanClient.uniqueDestination(for:in:) instead.
    public func fastDownload(_ scan: ScanEntry) async {
        guard client != nil else { return }
        selectedScanID = scan.id
        savedMessage = nil
        let destination = ScanClient.uniqueDestination(for: scan.name, in: downloadsDirectory)
        await save(scan, to: destination, thenOpen: false)
    }

    private func saveViaPanel(_ scan: ScanEntry, thenOpen: Bool) async {
        guard client != nil else { return }
        selectedScanID = scan.id
        savedMessage = nil

        let panel = NSSavePanel()
        panel.nameFieldStringValue = scan.name
        panel.directoryURL = downloadsDirectory
        panel.canCreateDirectories = true
        panel.prompt = "Save"
        panel.message = "Choose where to save \(scan.name)."
        let originalExtension = (scan.name as NSString).pathExtension
        // Held in a local var since NSSavePanel.delegate is weak.
        let extensionDelegate = originalExtension.isEmpty
            ? nil
            : ExtensionEnforcingPanelDelegate(requiredExtension: originalExtension)
        panel.delegate = extensionDelegate
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        await save(scan, to: destination, thenOpen: thenOpen)
    }

    private func save(_ scan: ScanEntry, to destination: URL, thenOpen: Bool) async {
        guard let client else { return }
        isBusy = true
        savingMessage = "Saving \(destination.lastPathComponent)…"
        defer { isBusy = false }

        do {
            try await client.save(scan, to: destination, cacheDirectory: cacheDirectory)
            if thenOpen { NSWorkspace.shared.open(destination) }
            savingMessage = nil
            savedMessage = "File \(destination.lastPathComponent) saved."
        } catch {
            savingMessage = nil
            state = .failed("Lost connection to \(hostInput) while saving \(scan.name).")
        }
    }

    // Footer trash button only; right-click "Move to Trash" skips this.
    public func requestDelete(_ scan: ScanEntry) {
        selectedScanID = scan.id
        pendingDelete = scan
    }

    // Failure flashes savingMessage rather than state = .failed(...).
    public func delete(_ scan: ScanEntry) async {
        guard let client else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await client.delete(scan)
            scans.removeAll { $0.id == scan.id }
            if selectedScanID == scan.id { selectedScanID = nil }
        } catch {
            savingMessage = "Couldn't delete \(scan.name)."
            try? await Task.sleep(for: .seconds(2))
            savingMessage = nil
        }
    }

    public nonisolated static func baseURL(fromHostInput input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        return URL(string: withScheme)
    }
}

private final class ExtensionEnforcingPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    let requiredExtension: String

    init(requiredExtension: String) {
        self.requiredExtension = requiredExtension
    }

    func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String? {
        // okFlag is false while typing; only rewrite once confirmed.
        guard okFlag else { return filename }
        let base = (filename as NSString).deletingPathExtension
        return "\(base.isEmpty ? filename : base).\(requiredExtension)"
    }
}
