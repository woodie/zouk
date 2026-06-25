import AppKit
import SwiftUI

/// Finder/Samba-share-style icon grid: PDF thumbnail above, filename below.
/// Click to select, "Download" copies the selected files to ~/Downloads.
struct ScanGridView: View {
    @ObservedObject var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 20)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.hostInput)
                    .font(.headline)
                Spacer()
                Button("Change Server") { model.changeServer() }
                Button("Refresh") { Task { await model.connect() } }
                    .disabled(model.isBusy)
            }
            .padding()

            Divider()

            content

            Divider()

            HStack {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Download (\(model.selected.count))") {
                    Task { await model.downloadSelected() }
                }
                .disabled(model.selected.isEmpty || model.isBusy)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.state.errorMessage {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(message)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await model.connect() } }
            }
            .frame(maxWidth: 320)
            Spacer()
        } else if model.scans.isEmpty {
            Spacer()
            Text(model.isBusy ? "Loading…" : "No scans found.")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(model.scans) { scan in
                        ScanThumbnailCell(scan: scan, model: model)
                    }
                }
                .padding()
            }
        }
    }
}

private struct ScanThumbnailCell: View {
    let scan: ScanEntry
    @ObservedObject var model: AppModel
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "doc.richtext")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                            .padding(20)
                    }
                }
                .frame(width: 96, height: 120)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(model.selected.contains(scan.id) ? Color.accentColor : Color.clear, lineWidth: 3)
                )

                if model.selected.contains(scan.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue)
                        .padding(4)
                }
            }
            Text(scan.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(scan) }
        .task { image = await model.thumbnail(for: scan) }
    }
}
