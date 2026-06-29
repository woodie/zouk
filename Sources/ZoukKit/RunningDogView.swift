import AppKit
import Combine
import ImageIO
import SwiftUI

/// Frame-by-frame playback of `RunningDog.gif` (an 8-frame run cycle,
/// already flipped to face left). ImageIO decodes the GIF directly so we
/// don't need to ship a separate PNG per frame or pull in a third-party
/// GIF-rendering dependency just to animate eight small images.
enum RunningDogAnimation {
    static let frames: [NSImage] = {
        guard
            let url = ZoukResources.bundle.url(forResource: "RunningDog", withExtension: "gif"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return [] }

        let count = CGImageSourceGetCount(source)
        return (0..<count).compactMap { index in
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }()

    /// Matches the source GIF's 100ms-per-frame timing rather than reading
    /// it back out of the file's per-frame metadata -- all eight frames
    /// share the same duration, so there's nothing per-frame to preserve.
    static let frameInterval: TimeInterval = 0.1
}

/// Loops `RunningDogAnimation.frames` on a timer. Falls back to the plain
/// (static) app icon if the GIF somehow failed to decode, so ConnectingView
/// always has something to show.
struct RunningDogView: View {
    @State private var frameIndex = 0

    private let timer = Timer.publish(every: RunningDogAnimation.frameInterval, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if RunningDogAnimation.frames.isEmpty {
                AppIconImage()
            } else {
                Image(nsImage: RunningDogAnimation.frames[frameIndex])
                    .resizable()
                    .scaledToFit()
            }
        }
        .onReceive(timer) { _ in
            guard !RunningDogAnimation.frames.isEmpty else { return }
            frameIndex = (frameIndex + 1) % RunningDogAnimation.frames.count
        }
    }
}
