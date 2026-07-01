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
    /// Transient overlay text shown while `open(_:)` is actively saving a
    /// file, e.g. "Saving 1782420815.pdf…", cleared the moment that
    /// finishes (success or failure) -- it's a quick heads-up mid-save, not
    /// the confirmation. Also reused by `delete(_:)` for a brief
    /// "Couldn't delete ..." flash on failure (a successful delete needs no
    /// message here -- the scan just vanishing from the grid is the
    /// confirmation).
    @Published public var savingMessage: String?
    /// Persistent footer text confirming the *last* file `open(_:)`
    /// saved, e.g. "File 1782420815.pdf saved." Deliberately silent on
    /// *where* -- the destination is whatever the user picked in the
    /// Save panel, which they just saw and chose themselves, so naming
    /// it again here isn't useful the way "...saved to Downloads" was
    /// back when Downloads was the only possible destination. Unlike
    /// `savingMessage`, this doesn't auto-clear on a timer -- it
    /// replaces the footer's usual scan-count/selection text and stays
    /// there until the user selects a scan (`toggle`, which swaps it for
    /// that scan's stats) or double-clicks another one (`open`, which
    /// clears it before starting the next save). A capsule that
    /// vanished after a second was too easy to miss; this sticks around
    /// until something else clearly needs the footer instead.
    @Published public var savedMessage: String?

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
        savedMessage = nil
        client = nil
        thumbnailCache.removeAll()
    }

    public var selectedScan: ScanEntry? {
        guard let selectedScanID else { return nil }
        return scans.first { $0.id == selectedScanID }
    }

    /// Single click: select/deselect for the info footer. Clicking the
    /// already-selected scan again deselects it. Selecting also clears
    /// any lingering "saved" footer message from a previous open(_:) --
    /// the footer can only show one thing at a time, and a fresh
    /// selection is the more useful thing to show.
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

    /// Double-click on a thumbnail: Now it always shows a native
    /// Save panel first, pre-filled with `scan.name` and ~/Downloads
    /// already selected, so confirming with no changes reproduces the
    /// old one-step behavior exactly, but renaming or picking a
    /// different folder is just as easy. Selects the scan unconditionally
    /// before the panel opens, the same as the old right-click/long-press
    /// Save As did, so cancelling the panel leaves it selected with its
    /// stats showing rather than clearing the footer for nothing.
    ///
    /// Whatever destination comes back from the panel, this still hands
    /// the saved file to NSWorkspace afterward -- the one part of the
    /// original "double-click opens it" idea worth keeping no matter
    /// where the file ends up. The grid's own listing is untouched
    /// either way: `scan.name` keeps showing whatever the server called
    /// it, only the local copy gets whatever name and folder the panel
    /// was given.
    ///
    /// The saved copy always keeps the scan's own extension (whatever
    /// the scanner actually produced -- usually .pdf, but nothing here
    /// assumes that), even if the user renames the file in the panel and
    /// drops or changes it. This deliberately isn't done via
    /// `panel.allowedContentTypes`: on confirm, that just *appends* its
    /// required extension to whatever's already there instead of
    /// replacing a mismatched one -- typing "foobar.zip" would become
    /// "foobar.zip.pdf", not "foobar.pdf". `ExtensionEnforcingPanelDelegate`
    /// intercepts the same moment and rewrites it properly instead.
    /// Skipped entirely on the rare scan name with no extension at all
    /// -- nothing to enforce.
    ///
    /// Shows `savingMessage` while the save's in flight, then swaps that
    /// for the persistent `savedMessage` once the file's on disk and
    /// handed off to NSWorkspace. No spinner, no animation -- just text,
    /// and the part that's meant to actually be noticed is the part that
    /// doesn't disappear on its own.
    public func open(_ scan: ScanEntry) async {
        guard let client else { return }
        selectedScanID = scan.id
        savedMessage = nil

        let panel = NSSavePanel()
        panel.nameFieldStringValue = scan.name
        panel.directoryURL = downloadsDirectory
        panel.canCreateDirectories = true
        panel.prompt = "Save"
        panel.message = "Choose where to save \(scan.name)."
        let originalExtension = (scan.name as NSString).pathExtension
        // Held here (not just assigned to panel.delegate) because
        // NSSavePanel.delegate is weak -- without a strong local
        // reference this would be deallocated before runModal() ever
        // shows the panel.
        let extensionDelegate = originalExtension.isEmpty
            ? nil
            : ExtensionEnforcingPanelDelegate(requiredExtension: originalExtension)
        panel.delegate = extensionDelegate
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isBusy = true
        savingMessage = "Saving \(destination.lastPathComponent)…"
        defer { isBusy = false }

        do {
            try await client.save(scan, to: destination, cacheDirectory: cacheDirectory)
            NSWorkspace.shared.open(destination)
            savingMessage = nil
            savedMessage = "File \(destination.lastPathComponent) saved."
        } catch {
            savingMessage = nil
            state = .failed("Lost connection to \(hostInput) while saving \(scan.name).")
        }
    }

    /// Deletes `scan` from the server (DELETE on the same path GET uses to
    /// download it -- see ScanClient.delete(_:)) and, on success, removes
    /// it from `scans`, clearing the selection if it was the one selected.
    /// The scan vanishing from the grid *is* the confirmation, the same way
    /// Finder just removes a deleted item rather than popping a separate
    /// "deleted" toast. On failure, this reuses the `savingMessage` overlay
    /// capsule for a brief "Couldn't delete ..." flash rather than routing
    /// through `state`: `state = .failed(...)` would swap the whole grid
    /// for the connectivity-error screen (see ScanGridView.content), which
    /// isn't the right response to a delete that failed on an otherwise-
    /// working connection. Called from ScanGridView's confirmation dialog,
    /// not directly from the trash button -- see confirmingDelete there.
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

    /// Pure, nonisolated so it's easy to unit test: prepends "http://" when
    /// the user didn't type a scheme, trims whitespace, rejects empty input.
    public nonisolated static func baseURL(fromHostInput input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        return URL(string: withScheme)
    }
}

/// Forces whatever filename ends up confirmed in an `NSSavePanel` to
/// always end in `requiredExtension`, by stripping any extension the
/// user actually typed (if any) and appending the required one in its
/// place -- once, never twice. Exists because `NSSavePanel.allowedContentTypes`
/// doesn't do this on its own: when the typed extension doesn't match,
/// it appends its required extension to the end rather than replacing
/// the mismatched one, so "foobar.zip" becomes "foobar.zip.pdf" instead
/// of "foobar.pdf".
private final class ExtensionEnforcingPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    let requiredExtension: String

    init(requiredExtension: String) {
        self.requiredExtension = requiredExtension
    }

    func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String? {
        // okFlag is false while the user's still typing (live validation);
        // only rewrite once they've actually committed to this name.
        guard okFlag else { return filename }
        let base = (filename as NSString).deletingPathExtension
        return "\(base.isEmpty ? filename : base).\(requiredExtension)"
    }
}
