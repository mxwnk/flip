import SwiftUI

/// Appearance of the overlay. Pure data, no logic.
enum Theme {
    /// One row up to the first threshold, one more past each further one.
    static let rowThresholds = [5, 12]

    /// A ceiling, not a size: tiles shrink below it as soon as the columns stop
    /// fitting. It binds with few windows on a wide screen, which is exactly when
    /// there is room to spare, so it is set generously.
    static let tileWidth: CGFloat = 420
    /// Thumbnail height relative to tile width. Near 16:9, which most windows are.
    static let thumbnailRatio: CGFloat = 0.58
    static let titleHeight: CGFloat = 34
    static let iconSize: CGFloat = 20
    static let tilePadding: CGFloat = 14
    static let tileRadius: CGFloat = 10

    static let panelPadding: CGFloat = 18
    static let panelRadius: CGFloat = 20
    /// Of the screen, before tiles are shrunk to fit.
    static let panelWidthFraction: CGFloat = 0.92

    static let fontSize: CGFloat = 13

    static let dim = Color(white: 0, opacity: 0.30)
    static let panel = Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.94)
    static let panelStroke = Color.white.opacity(0.10)
    static let tile = Color.white.opacity(0.05)
    static let selectedTile = Color.white.opacity(0.16)
    static let selectedStroke = Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.95)
    static let thumbnailBackground = Color.black.opacity(0.25)
    static let title = Color.white.opacity(0.92)
}
