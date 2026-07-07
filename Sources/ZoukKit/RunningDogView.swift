import AppKit
import Combine
import ImageIO
import SwiftUI

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

    static let frameInterval: TimeInterval = 0.1
}

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
