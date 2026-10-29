import AppKit
import SwiftUI

@MainActor
final class CountdownModel: ObservableObject {
    @Published var remaining: Int
    init(remaining: Int) { self.remaining = remaining }
}

/// Big "5…1" shown in the middle of the screen before a recording starts. Clicking it cancels.
@MainActor
enum Countdown {
    static let seconds = 5

    private static var panel: NSPanel?
    private static var timer: Timer?
    private static var completion: ((Bool) -> Void)?

    static var isActive: Bool { panel != nil }

    /// Calls `completion(true)` when the countdown ends, `completion(false)` when it is cancelled.
    static func run(on screen: NSScreen, completion: @escaping (Bool) -> Void) {
        cancel()
        self.completion = completion
        let model = CountdownModel(remaining: seconds)
        let hosting = NSHostingView(rootView: CountdownView(model: model, onCancel: { cancel() }))
        let size = NSSize(width: 220, height: 220)
        let frame = screen.frame
        let panel = NSPanel(contentRect: NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                                width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard Self.panel === panel else { return }
                if model.remaining > 1 {
                    model.remaining -= 1
                } else {
                    finish(true)
                }
            }
        }
    }

    static func cancel() { finish(false) }

    private static func finish(_ completed: Bool) {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        let completion = self.completion
        self.completion = nil
        guard let completion else { return }
        // Let the window server remove the panel before the first frame is captured.
        DispatchQueue.main.asyncAfter(deadline: .now() + (completed ? 0.15 : 0)) { completion(completed) }
    }
}

struct CountdownView: View {
    @ObservedObject var model: CountdownModel
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("\(model.remaining)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeInOut(duration: 0.25), value: model.remaining)
            Text(L("Клик — отмена"))
                .font(.system(size: 12, weight: .medium))
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .frame(width: 200, height: 200)
        .background(Circle().fill(.black.opacity(0.65)))
        .contentShape(Circle())
        .onTapGesture(perform: onCancel)
        .handCursor()
        .frame(width: 220, height: 220)
    }
}
