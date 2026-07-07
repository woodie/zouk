import SwiftUI

public struct ContentView: View {
    @StateObject private var model = AppModel()

    public init() {}

    public var body: some View {
        Group {
            // Checked before hasEverConnected to cover every in-flight connect(), not just the first.
            if model.state == .connecting {
                ConnectingView()
            } else if model.hasEverConnected {
                ScanGridView(model: model)
            } else {
                HostEntryView(model: model)
            }
        }
        // idealWidth/idealHeight (not just min) drive windowResizability(.contentSize)'s initial sizing.
        .frame(minWidth: 360, idealWidth: 420, minHeight: 280, idealHeight: 380)
    }
}
