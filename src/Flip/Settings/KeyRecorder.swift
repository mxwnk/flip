import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press the key. A text field takes only characters, and F1 to F12
/// are good bindings. Recording swallows the keystroke so nothing is typed into
/// the settings window on the way past; escape or a second click gives up.
struct KeyRecorder: View {
    @Binding var key: String

    /// Raised while armed. Flip's own tap would otherwise swallow a key already
    /// bound bare, F1 above all.
    var onCapture: ((Bool) -> Void)?

    var width: CGFloat = 54

    @State private var isRecording = false
    @State private var monitor: Any?
    /// So a pending timeout can only end the recording it was armed for.
    @State private var session = 0

    var body: some View {
        Button { isRecording ? stop() : start() } label: {
            Text(isRecording ? "press" : label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: width, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(fill))
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press the key, or escape to give up" : "Click, then press a key")
        .onDisappear(perform: stop)
    }

    private var label: String { key.isEmpty ? "key" : key.uppercased() }

    /// Lit like the keyboard below, where this key lights up too.
    private var fill: Color {
        isRecording ? Theme.selectedStroke : Color.primary.opacity(0.07)
    }

    private var ink: Color {
        if isRecording { return .white }

        return key.isEmpty ? .secondary : .primary
    }

    private func start() {
        guard monitor == nil else { return }

        session += 1
        let armed = session
        isRecording = true
        onCapture?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)

            return nil
        }

        // Left armed, Flip's own keys stay off and nothing says why.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard session == armed else { return }

            stop()
        }
    }

    private func record(_ event: NSEvent) {
        defer { stop() }

        guard Int(event.keyCode) != kVK_Escape,
              let recorded = KeyboardLayout.bindingKey(for: CGKeyCode(event.keyCode))
        else { return }

        // Longer input is only meaningful for named keys like F1.
        key = recorded.count == 1 ? recorded.lowercased() : recorded
    }

    private func stop() {
        guard let monitor else { return }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        isRecording = false
        session += 1
        onCapture?(false)
    }
}
