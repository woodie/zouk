import AppKit
import SwiftUI

public enum AppIcon {
    public static let nsImage: NSImage? = {
        guard let url = ZoukResources.bundle.url(forResource: "AppIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

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
            // Defensive fallback; AppIcon.png ships with the package.
            Image(systemName: "app.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}
