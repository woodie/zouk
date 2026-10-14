import AppKit
import SwiftUI

struct ScanGridView: View {
    @ObservedObject var model: AppModel
    @State private var isDropTargeted = false
    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 20)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { Task { await model.connect() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(CircularIconButtonStyle())
                .disabled(model.isBusy)
                .help("Reload")

                TextField("Hostname or IP address", text: $model.hostInput)
                    .textFieldStyle(.plain)
                    .disabled(model.isBusy)
                    .onSubmit { Task { await model.connect() } }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                Button { Task { await model.chooseFilesToUpload() } } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(CircularIconButtonStyle())
                .disabled(model.isBusy)
                .help("Upload files (or drop them on the window)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { model.selectedScanID = nil }
                // Files dragged in from Finder upload, like dropping them on a mounted share.
                .dropDestination(for: URL.self) { urls, _ in
                    let files = urls.filter(\.isFileURL)
                    guard !files.isEmpty, !model.isBusy else { return false }
                    Task { await model.upload(files) }
                    return true
                } isTargeted: { isDropTargeted = $0 }
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }

            Divider()

            footer
        }
        .overlay {
            if let saving = model.savingMessage {
                Text(saving)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .shadow(radius: 4)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.savingMessage)
        // presenting uses pendingDelete, not selectedScan; title mirrors the web page's confirm() text.
        .confirmationDialog(
            model.pendingDelete.map { "Delete \($0.name)?" } ?? "Delete this file?",
            isPresented: Binding(
                get: { model.pendingDelete != nil },
                set: { isPresented in if !isPresented { model.pendingDelete = nil } }
            ),
            presenting: model.pendingDelete
        ) { scan in
            Button("Delete", role: .destructive) {
                Task {
                    await model.delete(scan)
                    model.pendingDelete = nil
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            if let saved = model.savedMessage {
                Text(saved)
            } else if let scan = model.selectedScan {
                if let date = scan.formattedDate {
                    Text(date)
                }
                Text(scan.humanSize)
                Button {
                    model.requestDelete(scan)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete this file")
            } else {
                Text(model.scans.isEmpty ? "" : model.scans.count == 1 ? "1 file" : "\(model.scans.count) files")
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
                Text("Try again once that's sorted out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await model.connect() } }
            }
            .frame(maxWidth: 320)
            Spacer()
        } else if model.scans.isEmpty {
            Spacer()
            Text(model.isBusy ? "Loading…" : "No files yet. Drop files here to upload.")
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

private struct CircularIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .padding(6)
            .background(
                Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.09))
            )
            .contentShape(Circle())
    }
}

private struct DogEaredDocumentIcon: View {
    var body: some View {
        ZStack {
            PageShape()
                .fill(Color(nsColor: .textBackgroundColor))
            PageShape()
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            FoldShape()
                .fill(Color.secondary.opacity(0.25))
            FoldShape()
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 2)
    }

    private struct PageShape: Shape {
        var fold: CGFloat = 20
        var corner: CGFloat = 0

        func path(in rect: CGRect) -> Path {
            let width = rect.width, height = rect.height
            var path = Path()
            path.move(to: CGPoint(x: corner, y: 0))
            path.addLine(to: CGPoint(x: width - fold, y: 0))
            path.addLine(to: CGPoint(x: width, y: fold))
            path.addLine(to: CGPoint(x: width, y: height - corner))
            path.addArc(
                center: CGPoint(x: width - corner, y: height - corner), radius: corner,
                startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
            )
            path.addLine(to: CGPoint(x: corner, y: height))
            path.addArc(
                center: CGPoint(x: corner, y: height - corner), radius: corner,
                startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
            )
            path.addLine(to: CGPoint(x: 0, y: corner))
            path.addArc(
                center: CGPoint(x: corner, y: corner), radius: corner,
                startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
            )
            path.closeSubpath()
            return path
        }
    }

    private struct FoldShape: Shape {
        var fold: CGFloat = 20

        func path(in rect: CGRect) -> Path {
            let width = rect.width
            var path = Path()
            path.move(to: CGPoint(x: width - fold, y: 0))
            path.addLine(to: CGPoint(x: width, y: fold))
            path.addLine(to: CGPoint(x: width - fold, y: fold))
            path.closeSubpath()
            return path
        }
    }
}

private struct ScanThumbnailCell: View {
    let scan: ScanEntry
    @ObservedObject var model: AppModel
    @State private var image: NSImage?
    // Selection tint follows window key state, like Finder.
    @Environment(\.controlActiveState) private var controlActiveState

    private var isSelected: Bool { model.selectedScanID == scan.id }

    private var selectionTint: Color {
        controlActiveState == .key ? .accentColor : Color.secondary.opacity(0.6)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let image {
                    // Tuned against real side-by-side measurements on real hardware (huck's own
                    // placeholder-matched 76x96 read too small; 96x120 -- filling the full outer
                    // frame -- read too big; 86x108 still read a real ~13% larger than huck's
                    // thumbnail). 82x104 is the real-measurement-derived middle ground for a page.
                    // Backing, corners and the selection halo all go on the fitted image, before
                    // the max frame (which takes all the space it's offered), so they hug the
                    // picture: a page stays page-shaped, and a wide upload keeps its own shape,
                    // halo included, instead of sitting in a tall tile. The outer 108x132 matches
                    // the placeholder below, so the cell's footprint never changes.
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .modifier(SelectionHalo(isSelected: isSelected, tint: selectionTint))
                        .frame(maxWidth: 108, maxHeight: 116)
                        .frame(width: 108, height: 132)
                } else {
                    // Drawn, not clipped, so the dog-ear fold and shadow render like Finder's placeholder.
                    DogEaredDocumentIcon()
                        .frame(width: 76, height: 96)
                        .frame(width: 96, height: 120)
                        .modifier(SelectionHalo(isSelected: isSelected, tint: selectionTint))
                }
            }
            Text(scan.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isSelected ? selectionTint : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .contentShape(Rectangle())
        .help("Double-click to choose where to save, then open it. Right-click for more options.")
        // exclusively(before:) gives double-tap explicit precedence over single-tap.
        .gesture(
            TapGesture(count: 2)
                .onEnded { Task { await model.open(scan) } }
                .exclusively(
                    before: TapGesture(count: 1)
                        .onEnded { model.toggle(scan) }
                )
        )
        // Right-click menu reintroduced for issue #4.
        .contextMenu {
            Button {
                Task { await model.open(scan) }
            } label: {
                Label("Download and Open", systemImage: "arrow.up.right.square")
            }
            Button {
                Task { await model.downloadWithoutOpening(scan) }
            } label: {
                Label("Download to…", systemImage: "icloud.and.arrow.down")
            }
            Button {
                Task { await model.fastDownload(scan) }
            } label: {
                Label("Fast Download", systemImage: "arrow.down.circle.fill")
            }
            Divider()
            // Skips confirmation deliberately; see AppModel.requestDelete(_:).
            Button(role: .destructive) {
                Task { await model.delete(scan) }
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        .task { image = await model.thumbnail(for: scan) }
    }
}

// A tinted rounded tile plus a soft glow behind whatever it wraps. Padding stays constant so
// selection only toggles tint/shadow, not layout.
private struct SelectionHalo: ViewModifier {
    let isSelected: Bool
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? tint.opacity(0.15) : Color.clear)
            )
            .shadow(
                color: isSelected ? tint.opacity(0.55) : .clear,
                radius: isSelected ? 7 : 0,
                x: 0,
                y: isSelected ? 2 : 0
            )
    }
}
