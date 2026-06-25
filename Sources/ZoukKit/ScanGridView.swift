import AppKit
import SwiftUI

/// Finder/Samba-share-style icon grid: PDF thumbnail above, filename below.
/// Click selects a scan and shows its date/size in the footer; double-click
/// downloads it straight to ~/Downloads.
struct ScanGridView: View {
    @ObservedObject var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 20)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.changeServer() } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(CircularIconButtonStyle())
                .help("Change Server")

                Text(model.hostInput)
                    .font(.headline)

                Spacer()

                Button { Task { await model.connect() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(CircularIconButtonStyle())
                .disabled(model.isBusy)
                .help("Refresh")
            }
            .padding()

            Divider()

            content

            Divider()

            footer
        }
        .overlay(alignment: .top) {
            if let status = model.statusMessage {
                Text(status)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .shadow(radius: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.statusMessage)
    }

    /// Finder-style status bar: shows the clicked scan's date/size, or the
    /// total scan count when nothing's selected.
    @ViewBuilder
    private var footer: some View {
        HStack {
            if let scan = model.selectedScan {
                Text(scan.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let date = scan.downloadedAt {
                    Text(date, style: .date)
                }
                Text(scan.formattedSize)
            } else {
                Text(model.scans.isEmpty ? "" : "\(model.scans.count) scans")
                Spacer()
            }
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding()
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

/// Round toolbar button: subtle circle at rest, darker fill while pressed,
/// so a click has visible feedback instead of a bare floating icon.
private struct CircularIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .imageScale(.medium)
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.09))
            )
            .contentShape(Circle())
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
                        .stroke(model.selectedScanID == scan.id ? Color.accentColor : Color.clear, lineWidth: 3)
                )
            }
            Text(scan.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .help("Double-click to download")
        // Order matters: SwiftUI resolves the higher tap count first, only
        // falling back to the single-tap closure once the double-click
        // window has passed without a second tap.
        .onTapGesture(count: 2) { Task { await model.download(scan) } }
        .onTapGesture(count: 1) { model.toggle(scan) }
        .task { image = await model.thumbnail(for: scan) }
    }
}
