import AppKit
import Foundation
import SwiftUI
import ZoukKit

@main
struct ZoukApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(AppInfo.fullName) {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            // Menu label stays short to match "Hide Zouk"/"Quit Zouk"; the panel still shows the full name.
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppInfo.shortName)") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: AppInfo.fullName,
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Also sets the Dock icon for swift run/dev launches, not just the bundled .app.
        NSApp.applicationIconImage = AppIcon.nsImage
    }
}
