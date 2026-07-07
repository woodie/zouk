import Foundation

// Contents/Resources first (required once signed); Bundle.module fallback for swift run/test.
enum ZoukResources {
    static let bundle: Bundle = {
        if
            let resourceURL = Bundle.main.resourceURL,
            let contents = try? FileManager.default.contentsOfDirectory(
                at: resourceURL,
                includingPropertiesForKeys: nil
            ),
            let zoukKitBundleURL = contents.first(where: { $0.lastPathComponent.hasSuffix("_ZoukKit.bundle") }),
            let bundle = Bundle(url: zoukKitBundleURL) {
            return bundle
        }
        return Bundle.module
    }()
}
