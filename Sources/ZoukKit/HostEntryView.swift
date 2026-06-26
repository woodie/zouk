import SwiftUI

/// First screen the user sees, and the one they come back to via "Change
/// Server". Remembers the last host (AppModel persists it to UserDefaults
/// on successful connect) and shows a plain-language error inline if the
/// server can't be reached.
struct HostEntryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Connect to your scans")
                .font(.title2)

            Text("macOS may ask for local network permission the first time — if it fails, just try again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 280)

            TextField("Hostname or IP address", text: $model.hostInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .disabled(model.isBusy)
                .onSubmit { Task { await model.connect() } }

            if let message = model.state.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
            }

            Button("Connect") {
                Task { await model.connect() }
            }
            .disabled(model.hostInput.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 280)
    }
}
