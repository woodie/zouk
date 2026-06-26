import AppKit
import SwiftUI

/// The app's icon artwork, loaded directly from the package bundle so it
/// renders identically in every run mode (`swift run`, `make run`, Xcode)
/// instead of depending on the hand-assembled .app bundle's Info.plist /
/// Contents/Resources/AppIcon.icns the way `NSApp.applicationIconImage`
/// would on its own.
///
/// `public` because `ZoukApp.swift` (the `zouk` executable target, a
/// separate module) also needs it to set the Dock icon at launch.
public enum AppIcon {
    public static let nsImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// SwiftUI wrapper around `AppIcon.nsImage`, for dropping the icon into a
/// view hierarchy -- currently just HostEntryView's connect screen. Clips
/// to a rounded square -- macOS already auto-masks the Dock/.icns icon
/// into that same "squircle" shape since Big Sur, so this just matches
/// that native app-icon look wherever the art shows up inside the UI
/// itself, where nothing clips it for us. (The native About panel, shown
/// via `NSApplication.orderFrontStandardAboutPanel` in ZoukApp.swift,
/// gets its icon straight from `NSApp.applicationIconImage` instead.)
///
/// The corner radius is computed from whatever size the call site frames
/// this view at (via GeometryReader) rather than a fixed point value, so
/// it stays proportionally correct at any size used later -- matching the
/// ~22% of width Apple uses for its own app icon corner radius.
struct AppIconImage: View {
    var body: some View {
        GeometryReader { geometry in
            content
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: min(geometry.size.width, geometry.size.height) * 0.22,
                        style: .continuous
                    )
                )
        }
    }

    @ViewBuilder
    private var content: some View {
        if let nsImage = AppIcon.nsImage {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            // Should never happen -- Resources/AppIcon.png ships with the
            // package -- but fall back to something rather than a blank
            // space if it's ever missing.
            Image(systemName: "app.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}
