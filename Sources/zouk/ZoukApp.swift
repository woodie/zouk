import AppKit
import SwiftUI
import ZoukKit

@main
struct ZoukApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("zouk") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
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
    }
}
