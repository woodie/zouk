import SwiftUI

/// First screen the user sees, and the one they come back to whenever a
/// connect attempt fails (ContentView routes there any time AppModel isn't
/// connected and isn't actively connecting -- see ConnectingView for the
/// in-flight state). Remembers the last host: AppModel persists it to
/// UserDefaults on successful connect and prefills it here next launch.
struct HostEntryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            AppIconImage()
                .frame(width: 64, height: 64)

            Text("You may be prompted for network access.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Hostname or IP address", text: $model.hostInput)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 280)
                .onSubmit { Task { await model.connect() } }

            Button("Connect") {
                Task { await model.connect() }
            }
            .disabled(model.hostInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 280)
    }
}
