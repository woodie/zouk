import AppKit
import Foundation
import SwiftUI
import ZoukKit

@main
struct ZoukApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Zouk scan retriever") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            // Replaces the default "About zouk" item (which would otherwise
            // show the bundle's literal CFBundleName, "zouk") with one that
            // calls the same native panel, just with our full display name
            // and a copyright credits line -- no separate custom About
            // window/sheet to build or maintain.
            CommandGroup(replacing: .appInfo) {
                Button("About Zouk scan retriever") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Zouk scan retriever",
                        .credits: NSAttributedString(
                            string: "© \(currentYear) John Woodell",
                            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                        )
                    ])
                }
            }
        }
    }
}

private var currentYear: String {
    String(Calendar.current.component(.year, from: Date()))
}

/// `swift run` launches zouk as a bare process with no .app bundle, so
/// macOS doesn't hand it keyboard focus/the menu bar the way it would an
/// app double-clicked from Finder: the window appears (you can even drag
/// it) but it never becomes the active app, so it can't receive keystrokes.
/// Forcing activation on launch fixes that.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Sets the Dock icon for `swift run`/dev launches too, not just the
        // hand-bundled .app (which gets it from Info.plist's
        // CFBundleIconFile / Contents/Resources/AppIcon.icns).
        NSApp.applicationIconImage = AppIcon.nsImage
    }
}
