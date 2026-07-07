import Foundation

/// Resolves ZoukKit's resource bundle (icon art, the running-dog GIF).
///
/// Looks in `Contents/Resources` first, via `Bundle.main.resourceURL` --
/// the conventional macOS location, and the *only* one `codesign` permits
/// once the app is actually signed. Putting anything outside `Contents/`
/// (which an earlier fix did, to work around the SwiftPM-generated
/// `Bundle.module` accessor never checking `resourceURL`) makes `codesign
/// --sign` fail outright with "unsealed contents present in the bundle
/// root" -- not just a notarization-time rejection, a hard signing error.
/// See docs/COWORK.md's "Packaging gotcha" note for the full history.
///
/// Falls back to `Bundle.module` for `swift run`/`swift test`/Xcode,
/// where `Bundle.main` isn't a real `.app` and `resourceURL` won't point
/// anywhere useful -- that's the one context where touching the generated
/// accessor is still safe (and necessary).
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
