import SwiftUI

/// The leader as keys rather than as a menu. Which modifier this is comes down
/// to where your thumb already rests and what else is bound on the machine —
/// both questions you answer by looking at keys, not by reading a list. The
/// symbols carry their words for the same reason the keyboard below does.
struct LeaderPicker: View {
    @Binding var choice: ModifierChoice

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ModifierChoice.allCases) { option in
                Button { choice = option } label: { cap(option) }
                    .buttonStyle(.plain)
                    .help("Hold \(option.spelled) and press a key")
            }
        }
    }

    // Named steps rather than one chain: the type checker gives up on the whole
    // thing in a single expression.
    private func cap(_ option: ModifierChoice) -> some View {
        let chosen = option == choice
        let ink: Color = chosen ? .white : .primary
        let fill: Color = chosen ? Theme.selectedStroke : Color(nsColor: .controlBackgroundColor)

        return VStack(spacing: 2) {
            Text(option.label)
                .font(.system(size: 18, weight: .medium))
            Text(option.spelled)
                .font(.system(size: 9))
                // The words are what this is for, so they shrink rather than
                // truncate — "comm…" helps nobody.
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .opacity(chosen ? 0.9 : 0.6)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fill)
                .shadow(color: .black.opacity(chosen ? 0 : 0.12), radius: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(chosen ? 0 : 0.10), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
