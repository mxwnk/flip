import SwiftUI

/// Read-only for now: these keys are fixed, and a list that looked editable but
/// was not would be worse than one that says so.
struct WindowActionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Move and resize the window you are working in.")
                    .font(.callout)
                Text("Halves and filling stop at the menu bar and the Dock. Filling a "
                     + "window that already fills puts it back where it was.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // A fixed handful of rows, so no scroll view: the note below belongs
            // with the list rather than pinned to the bottom of the window.
            ForEach(WindowArrangement.shortcuts) { shortcut in
                Divider().opacity(0.4)
                row(for: shortcut)
            }
            Divider().opacity(0.4)

            Text("These keys cannot be changed yet. Every single modifier is already "
                + "taken with the arrows: Option moves by word, Control switches spaces, "
                + "fn is Home and End, and Command is the start and end of a line.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Spacer(minLength: 0)
        }
    }

    private func row(for shortcut: WindowShortcut) -> some View {
        HStack {
            Text(shortcut.name)

            Spacer(minLength: 16)

            Text(shortcut.keys)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.07))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}
