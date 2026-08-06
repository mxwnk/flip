import SwiftUI

@MainActor
final class OverlayModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selected = 0
    @Published var layout = OverlayLayout(count: 0, screen: .zero)
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ZStack {
            Theme.dim

            VStack(spacing: Theme.tilePadding) {
                ForEach(rows, id: \.first?.id) { row in
                    HStack(spacing: Theme.tilePadding) {
                        ForEach(row) { window in
                            TileView(
                                window: window,
                                isSelected: window.id == selectedID,
                                layout: model.layout
                            )
                        }
                    }
                }
            }
            .padding(Theme.panelPadding)
            .background(
                RoundedRectangle(cornerRadius: Theme.panelRadius)
                    .fill(Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.panelRadius)
                            .strokeBorder(Theme.panelStroke, lineWidth: 1)
                    )
            )
        }
        .ignoresSafeArea()
    }

    private var selectedID: CGWindowID? {
        model.windows.indices.contains(model.selected) ? model.windows[model.selected].id : nil
    }

    /// The layout fixes the column count, so the flat list is cut to match rather
    /// than being allowed to wrap on its own.
    private var rows: [[WindowInfo]] {
        stride(from: 0, to: model.windows.count, by: max(model.layout.columns, 1)).map { start in
            Array(model.windows[start..<min(start + model.layout.columns, model.windows.count)])
        }
    }
}

private struct TileView: View {
    let window: WindowInfo
    let isSelected: Bool
    let layout: OverlayLayout

    var body: some View {
        VStack(spacing: 0) {
            // Kept even though step four has nothing to put in it: step five fills
            // this exact rectangle with a thumbnail and the layout must not move.
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.thumbnailBackground)
                .overlay(icon)
                .frame(height: layout.thumbnailHeight - Theme.tilePadding / 2)

            HStack(spacing: 6) {
                Image(nsImage: AppIconCache.icon(for: window.bundleID) ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Theme.iconSize, height: Theme.iconSize)

                Text(window.title.isEmpty ? window.applicationName : window.title)
                    .font(.system(size: Theme.fontSize))
                    .foregroundStyle(Theme.title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .frame(height: Theme.titleHeight)
        }
        .padding(Theme.tilePadding / 2)
        .frame(width: layout.tileWidth, height: layout.tileHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.tileRadius)
                .fill(isSelected ? Theme.selectedTile : Theme.tile)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.tileRadius)
                        .strokeBorder(isSelected ? Theme.selectedStroke : .clear, lineWidth: 2)
                )
        )
    }

    /// Stands in for the missing thumbnail, and is what a minimised window will
    /// keep showing even once thumbnails exist — a minimised window cannot be
    /// captured.
    private var icon: some View {
        Image(nsImage: AppIconCache.icon(for: window.bundleID) ?? NSImage())
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 64, height: 64)
            .opacity(0.85)
    }
}
