import SwiftUI

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
