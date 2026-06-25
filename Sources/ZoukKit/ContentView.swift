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
        .frame(minWidth: 480, minHeight: 360)
    }
}
