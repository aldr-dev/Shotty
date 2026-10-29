import AppKit
import SwiftUI

/// Floating pause/stop controls and the red frame shown while recording. Shotty's own windows are
/// excluded from the capture, so neither appears in the video.
@MainActor
final class RecordingControls {
    static let shared = RecordingControls()
    private var panel: NSPanel?
    private var frameWindow: NSWindow?

    func show(for selection: RegionSelection) {
        hide()
        let compact = selection.screen.visibleFrame.width < 1000
        let hosting = NSHostingView(rootView: RecordingControlsView(recorder: .shared, compact: compact))
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.setFrameOrigin(Self.origin(for: size, around: selection))
        panel.orderFrontRegardless()
        self.panel = panel

        if selection.rect != nil { showFrame(selection.globalFrame) }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        frameWindow?.orderOut(nil)
        frameWindow = nil
    }

    /// Below the recorded area if there's room, otherwise above it, otherwise inside its top edge.
    private static func origin(for size: NSSize, around selection: RegionSelection) -> NSPoint {
        let visible = selection.screen.visibleFrame
        let area = selection.globalFrame
        var origin = NSPoint(x: area.midX - size.width / 2, y: 0)
        if selection.rect == nil {
            origin.y = visible.minY + 24
        } else if area.minY - 14 - size.height >= visible.minY + 8 {
            origin.y = area.minY - 14 - size.height
        } else if area.maxY + 14 + size.height <= visible.maxY - 8 {
            origin.y = area.maxY + 14
        } else {
            origin.y = min(area.maxY, visible.maxY) - size.height - 14
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        return origin
    }

    private func showFrame(_ area: CGRect) {
        let frame = area.insetBy(dx: -3, dy: -3)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let border = NSView(frame: NSRect(origin: .zero, size: frame.size))
        border.wantsLayer = true
        border.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        border.layer?.borderWidth = 2
        window.contentView = border
        window.orderFrontRegardless()
        frameWindow = window
    }
}

struct RecordingControlsView: View {
    @ObservedObject var recorder: ScreenRecorder
    let compact: Bool
    @State private var blink = false

    private var paused: Bool { recorder.state == .paused }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(paused ? Color.orange : Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(paused || blink ? 1 : 0.35)
                Text(Self.format(recorder.elapsed))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if !compact {
                    Text(paused ? L("Пауза") : L("Запись"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            if let options = recorder.options {
                HStack(spacing: 4) {
                    Image(systemName: options.systemAudio ? "speaker.wave.2.fill" : "speaker.slash")
                        .help(options.systemAudio ? L("Системный звук записывается") : L("Без системного звука"))
                    Image(systemName: options.microphone ? "mic.fill" : "mic.slash")
                        .help(options.microphone ? L("Микрофон записывается") : L("Без микрофона"))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Divider().frame(height: 22)
            Button {
                recorder.togglePause()
            } label: {
                Label(paused ? L("Продолжить") : L("Пауза"), systemImage: paused ? "play.fill" : "pause.fill")
                    .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                    .frame(minWidth: compact ? 20 : 96)
            }
            .help(paused ? L("Продолжить запись") : L("Поставить на паузу"))
            Button {
                recorder.stop()
            } label: {
                Label(L("Завершить"), systemImage: "stop.fill")
                    .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            }
            .tint(.red)
            .buttonStyle(.borderedProminent)
            .help(L("Завершить запись"))
        }
        .controlSize(.large)
        .disabled(recorder.state == .finishing)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .fixedSize()
        .onReceive(Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()) { _ in blink.toggle() }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
