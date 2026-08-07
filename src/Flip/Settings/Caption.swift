import SwiftUI

/// The explanatory line under a group of settings. Every tab needs one and each
/// used to style it separately, which is how the four of them drifted apart.
struct Caption: View {
    private let text: String
    private let tone: Color

    init(_ text: String, tone: Color = .secondary) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tone)
            // Otherwise a long line is truncated rather than wrapped.
            .fixedSize(horizontal: false, vertical: true)
    }
}
