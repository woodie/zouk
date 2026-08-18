// The app's own name, in the two forms it's shown in across the UI: the full descriptive name
// (main window's title bar, About panel content) and the short form macOS's system app-menu
// forces on "Hide Zouk"/"Quit Zouk" (derived from CFBundleName, "zouk", auto-capitalized by
// AppKit). Lives here, in ZoukKit, not in Sources/zouk/ZoukApp.swift -- same reason
// ContentView/AppModel/etc. live here and not in the "zouk" executable target: only ZoukKit is
// @testable importable (see Package.swift's own comment on the executable-testability caveat).
// huck's AppInfo.kt doesn't need this split: a single Gradle module's src/test source set
// already sees src/main directly, no separate testable module required.
public enum AppInfo {
    /// Matches macOS's own "Hide Zouk"/"Quit Zouk" -- also used for the About menu item's own
    /// label (see ZoukApp.swift) so all three read alike, instead of that one item alone
    /// carrying the full name.
    public static let shortName = "Zouk"

    /// The full, descriptive name -- shown in the main window's title bar and inside the About
    /// panel's content (NSApplication.orderFrontStandardAboutPanel's .applicationName option),
    /// never in a menu item's own label.
    public static let fullName = "\(shortName) scan retriever"
}
