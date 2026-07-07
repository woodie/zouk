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
            // Replaces the default About item so it shows our full name + credits, not the raw CFBundleName.
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Also sets the Dock icon for swift run/dev launches, not just the bundled .app.
        NSApp.applicationIconImage = AppIcon.nsImage
    }
}
