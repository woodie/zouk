import SwiftUI

/// Shown while `AppModel.connect()` is in flight -- the automatic reconnect
/// attempt on launch and a manual retry both pass through here -- so
/// there's something more alive on screen than a static form while we wait
/// on the network.
struct ConnectingView: View {
    var body: some View {
        VStack(spacing: 16) {
            RunningDogView()
                .frame(width: 128, height: 128)

            Text("Fetching scans…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 280)
    }
}
