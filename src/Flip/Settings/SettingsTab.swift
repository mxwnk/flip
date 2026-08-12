import SwiftUI

/// One page of the settings window, and how it introduces itself. The sidebar,
/// the heading above the page and the keyboard below it all ask this rather than
/// each carrying its own copy of the title.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case switcher
    case shortcuts
    case windows
    case excluded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .switcher: return "Switcher"
        case .shortcuts: return "Shortcuts"
        case .windows: return "Windows"
        case .excluded: return "Excluded"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        // The grid it draws, which is what the page is about — and not the
        // window symbol, which belongs to the page next to it.
        case .switcher: return "square.grid.2x2.fill"
        case .shortcuts: return "keyboard.fill"
        case .windows: return "macwindow.on.rectangle"
        case .excluded: return "eye.slash.fill"
        }
    }

    /// Colour is what makes a row findable without reading it, so each page
    /// keeps its own and the grey one is the page that is about everything.
    var tint: Color {
        switch self {
        case .general: return Color(red: 0.42, green: 0.42, blue: 0.45)
        case .switcher: return Color(red: 0.10, green: 0.70, blue: 0.62)
        case .shortcuts: return Color(red: 0.20, green: 0.52, blue: 0.98)
        case .windows: return Color(red: 0.42, green: 0.36, blue: 0.90)
        case .excluded: return Color(red: 0.98, green: 0.55, blue: 0.20)
        }
    }
}

/// The rounded tile behind a page's symbol, small in the sidebar and larger
/// above the page itself.
struct SettingsIcon: View {
    let tab: SettingsTab
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tab.tint)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: tab.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}
