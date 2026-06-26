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
            // Browser-style: reload on the left, an address bar you can
            // just type into stretching the rest of the way to the window's
            // edge -- no separate "click to edit" step.
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { model.selectedScanID = nil }

            Divider()

            footer
        }
        .overlay {
            if let status = model.statusMessage {
                Text(status)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .shadow(radius: 4)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.statusMessage)
    }

    /// Finder-style status bar: shows the clicked scan's date and size --
    /// the scan's own filename is server-generated and never meaningful, so
    /// it doesn't belong here -- or the total scan count when nothing's
    /// selected. Centered either way.
    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            if let host = model.unreachableHost {
                Text("Can't reach \(host)")
            } else if let scan = model.selectedScan {
                if let date = scan.formattedDate {
                    Text(date)
                }
                Text(scan.formattedSize)
            } else {
                Text(model.scans.isEmpty ? "" : "\(model.scans.count) scans")
            }
            Spacer()
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
                Text("Try again once that's sorted out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

/// Circular icon-only toolbar button (e.g. the address bar's reload
/// button), subtle fill at rest, darker while pressed.
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

/// Generic "no preview yet" document icon: a white page with the top-right
/// corner folded down and a soft drop shadow, the same idea as the default
/// icon Finder shows for a file it hasn't generated a thumbnail for yet.
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

    /// Page outline with a diagonal cut out of the top-right corner (where
    /// the fold sits) and square corners everywhere else -- a plain sheet
    /// of paper, not a rounded card.
    private struct PageShape: Shape {
        var fold: CGFloat = 20
        var corner: CGFloat = 0

        func path(in rect: CGRect) -> Path {
            let w = rect.width, h = rect.height
            var path = Path()
            path.move(to: CGPoint(x: corner, y: 0))
            path.addLine(to: CGPoint(x: w - fold, y: 0))
            path.addLine(to: CGPoint(x: w, y: fold))
            path.addLine(to: CGPoint(x: w, y: h - corner))
            path.addArc(center: CGPoint(x: w - corner, y: h - corner), radius: corner, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: corner, y: h))
            path.addArc(center: CGPoint(x: corner, y: h - corner), radius: corner, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: corner))
            path.addArc(center: CGPoint(x: corner, y: corner), radius: corner, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.closeSubpath()
            return path
        }
    }

    /// The little triangular flap at the top-right, as if that corner were
    /// folded down over the page.
    private struct FoldShape: Shape {
        var fold: CGFloat = 20

        func path(in rect: CGRect) -> Path {
            let w = rect.width
            var path = Path()
            path.move(to: CGPoint(x: w - fold, y: 0))
            path.addLine(to: CGPoint(x: w, y: fold))
            path.addLine(to: CGPoint(x: w - fold, y: fold))
            path.closeSubpath()
            return path
        }
    }
}

private struct ScanThumbnailCell: View {
    let scan: ScanEntry
    @ObservedObject var model: AppModel
    @State private var image: NSImage?
    // Mirrors Finder: the icon itself stays plain, only the filename label
    // gets the selection highlight, and that highlight is blue while this
    // window is key and dims to gray once it isn't (matches the system's
    // own active/inactive selection tint instead of always being blue).
    @Environment(\.controlActiveState) private var controlActiveState

    private var isSelected: Bool { model.selectedScanID == scan.id }

    private var selectionTint: Color {
        controlActiveState == .key ? .accentColor : Color.secondary.opacity(0.6)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 120)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    // Drawn (not a clipped background) so the dog-ear fold
                    // and drop shadow read as a generic document icon, like
                    // the placeholder Finder shows for an unpreviewed file
                    // on a mounted share. Sized a bit smaller than the cell
                    // itself so it doesn't look bulkier than an actual scan
                    // thumbnail sitting in the same spot.
                    DogEaredDocumentIcon()
                        .frame(width: 76, height: 96)
                        .frame(width: 96, height: 120)
                }
            }
            // Padding is unconditional so the cell doesn't resize/jitter on
            // select; only the tint and shadow turn on, as a halo around the
            // thumbnail that echoes the filename's selection color.
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? selectionTint.opacity(0.15) : Color.clear)
            )
            .shadow(
                color: isSelected ? selectionTint.opacity(0.55) : .clear,
                radius: isSelected ? 7 : 0,
                x: 0,
                y: isSelected ? 2 : 0
            )
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
        .help("Double-click to download")
        // Order matters: SwiftUI resolves the higher tap count first, only
        // falling back to the single-tap closure once the double-click
        // window has passed without a second tap.
        .onTapGesture(count: 2) { Task { await model.download(scan) } }
        .onTapGesture(count: 1) { model.toggle(scan) }
        .task { image = await model.thumbnail(for: scan) }
    }
}
