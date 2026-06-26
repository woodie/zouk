import SwiftUI

public struct ContentView: View {
    // Property-initializer form (not a default argument on a custom init)
    // so AppModel(), a @MainActor type, is constructed the same way every
    // other SwiftUI @StateObject view model is -- the pattern Swift's
    // actor-isolation checker is tuned to accept without a custom init
    // having to itself be @MainActor.
    @StateObject private var model = AppModel()

    public init() {}

    public var body: some View {
        Group {
            if model.hasEverConnected {
                ScanGridView(model: model)
            } else {
                HostEntryView(model: model)
            }
        }
        // Open small like Finder does for a network share with a handful of
        // items in it -- idealWidth/idealHeight (not just min) is what
        // .windowResizability(.contentSize) actually uses to size the
        // window on first launch, so without them the window defaults to
        // something much larger than the content needs.
        .frame(minWidth: 360, idealWidth: 420, minHeight: 280, idealHeight: 380)
    }
}
