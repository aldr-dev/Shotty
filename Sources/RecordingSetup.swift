import AppKit
import Combine
import SwiftUI

struct RegionSelection {
    let screen: NSScreen
    /// In screen-local points with a bottom-left origin; nil means the whole screen.
    let rect: CGRect?

    /// The recorded area in global screen coordinates.
    var globalFrame: CGRect {
        guard let rect else { return screen.frame }
        return rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }
}

final class RecordingSetupModel: ObservableObject {
    @Published var screen: NSScreen
    @Published var rect: CGRect?
    @Published var isDragging = false
    @Published var compact = false

    init(screen: NSScreen) { self.screen = screen }

    var canStart: Bool { RecordingSettings.shared.area == .fullScreen || rect != nil }
}

/// Full-screen overlay plus a toolbar for choosing what to record and with which audio.
@MainActor
final class RecordingSetup {
    private static var current: RecordingSetup?

    private let model: RecordingSetupModel
    private let settings = RecordingSettings.shared
    private var overlays: [OverlayWindow] = []
    private var toolbar: NSPanel?
    private var hosting: NSHostingView<RecordingToolbar>?
    private var observers: Set<AnyCancellable> = []
    private let completion: (RegionSelection?) -> Void

    static var isActive: Bool { current != nil }

    static func begin(completion: @escaping (RegionSelection?) -> Void) {
        guard current == nil else { return }
        let setup = RecordingSetup(completion: completion)
        current = setup
        setup.show()
    }

    private init(completion: @escaping (RegionSelection?) -> Void) {
        self.completion = completion
        let mouse = NSEvent.mouseLocation
        model = RecordingSetupModel(screen: NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0])
    }

    private func show() {
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), screen: screen, model: model)
            view.onStart = { [weak self] in self?.start() }
            view.onCancel = { [weak self] in self?.finish(nil) }
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            overlays.append(window)
            if screen == model.screen {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
            } else {
                window.orderFrontRegardless()
            }
        }

        let hosting = NSHostingView(rootView: RecordingToolbar(model: model,
                                                               onCancel: { [weak self] in self?.finish(nil) },
                                                               onStart: { [weak self] in self?.start() }))
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        self.hosting = hosting
        toolbar = panel

        model.objectWillChange.merge(with: settings.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &observers)

        refresh()
        panel.orderFrontRegardless()
        NSApp.activate()
    }

    private func refresh() {
        for window in overlays {
            window.contentView?.needsDisplay = true
            window.invalidateCursorRects(for: window.contentView!)
        }
        let compact = model.screen.visibleFrame.width < 1000
        if model.compact != compact { model.compact = compact }
        toolbar?.alphaValue = model.isDragging ? 0 : 1
        placeToolbar()
    }

    private func placeToolbar() {
        guard let toolbar, let hosting else { return }
        let size = hosting.fittingSize
        let visible = model.screen.visibleFrame
        var frame = NSRect(x: visible.midX - size.width / 2, y: visible.minY + 28, width: size.width, height: size.height)

        if settings.area == .area, let rect = model.rect {
            let area = rect.offsetBy(dx: model.screen.frame.minX, dy: model.screen.frame.minY)
            if frame.intersects(area.insetBy(dx: -10, dy: -10)) {
                frame.origin.x = area.midX - size.width / 2
                if area.minY - 16 - size.height >= visible.minY + 8 {
                    frame.origin.y = area.minY - 16 - size.height
                } else if area.maxY + 16 + size.height <= visible.maxY - 8 {
                    frame.origin.y = area.maxY + 16
                } else {
                    frame.origin.y = area.minY + 16
                }
            }
        }
        frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - size.width - 8)
        toolbar.setFrame(frame, display: true)
    }

    private func start() {
        guard model.canStart else { return }
        let rect = settings.area == .area ? model.rect : nil
        finish(RegionSelection(screen: model.screen, rect: rect))
    }

    private func finish(_ selection: RegionSelection?) {
        observers.removeAll()
        toolbar?.orderOut(nil)
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        toolbar = nil
        RecordingSetup.current = nil
        completion(selection)
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    var onStart: (() -> Void)?
    var onCancel: (() -> Void)?
    private let screen: NSScreen
    private let model: RecordingSetupModel
    private var dragStart: NSPoint?
    private var moveOffset: NSPoint?

    init(frame: NSRect, screen: NSScreen, model: RecordingSetupModel) {
        self.screen = screen
        self.model = model
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isAreaMode: Bool { RecordingSettings.shared.area == .area }
    private var isActiveScreen: Bool { model.screen == screen }
    private var myRect: CGRect? { isActiveScreen ? model.rect : nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if isAreaMode {
            addCursorRect(bounds, cursor: .crosshair)
            if let rect = myRect { addCursorRect(rect, cursor: .openHand) }
        } else {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !isActiveScreen { model.screen = screen }
        window?.makeKey()
        window?.makeFirstResponder(self)

        if event.clickCount == 2, !isAreaMode || myRect?.contains(p) == true {
            onStart?()
            return
        }
        guard isAreaMode else { return }
        if let rect = myRect, rect.contains(p) {
            moveOffset = NSPoint(x: p.x - rect.minX, y: p.y - rect.minY)
            NSCursor.closedHand.set()
        } else {
            dragStart = p
            model.rect = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isAreaMode else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let offset = moveOffset, let rect = model.rect {
            var origin = NSPoint(x: p.x - offset.x, y: p.y - offset.y)
            origin.x = min(max(origin.x, 0), bounds.width - rect.width)
            origin.y = min(max(origin.y, 0), bounds.height - rect.height)
            model.rect = CGRect(origin: origin, size: rect.size).integral
        } else if let start = dragStart {
            model.isDragging = true
            model.rect = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
                .intersection(bounds).integral
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil, let rect = model.rect, rect.width < 16 || rect.height < 16 { model.rect = nil }
        dragStart = nil
        moveOffset = nil
        model.isDragging = false
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: onCancel?()
        case 36, 76: onStart?()
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isAreaMode {
            NSColor.black.withAlphaComponent(0.4).setFill()
            bounds.fill()
            if let rect = myRect {
                NSColor.clear.setFill()
                rect.fill(using: .copy)
                NSColor.white.setStroke()
                let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
                border.lineWidth = 1
                border.stroke()
                let label = "\(Int(rect.width)) × \(Int(rect.height))"
                let y = rect.maxY + 30 < bounds.maxY ? rect.maxY + 6 : rect.maxY - 30
                drawLabel(label, at: NSPoint(x: rect.minX, y: y), fontSize: 12, centered: false)
            } else if isActiveScreen && model.rect == nil {
                drawLabel(L("Выделите мышью область для записи"), at: NSPoint(x: bounds.midX, y: bounds.midY), fontSize: 16, centered: true)
            }
        } else if isActiveScreen {
            NSColor.black.withAlphaComponent(0.08).setFill()
            bounds.fill()
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 3, dy: 3))
            border.lineWidth = 6
            border.stroke()
            drawLabel(L("Будет записан весь этот экран"), at: NSPoint(x: bounds.midX, y: bounds.midY), fontSize: 16, centered: true)
        } else {
            NSColor.black.withAlphaComponent(0.45).setFill()
            bounds.fill()
            drawLabel(L("Щёлкните, чтобы записать этот экран"), at: NSPoint(x: bounds.midX, y: bounds.midY), fontSize: 16, centered: true)
        }
    }

    private func drawLabel(_ text: String, at point: NSPoint, fontSize: CGFloat, centered: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let padX: CGFloat = fontSize, padY: CGFloat = fontSize * 0.45
        var box = NSRect(x: point.x, y: point.y, width: size.width + padX * 2, height: size.height + padY * 2)
        if centered { box.origin = NSPoint(x: point.x - box.width / 2, y: point.y - box.height / 2) }
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + padX, y: box.minY + padY), withAttributes: attrs)
    }
}

// MARK: - Toolbar

struct RecordingToolbar: View {
    @ObservedObject var model: RecordingSetupModel
    @ObservedObject private var settings = RecordingSettings.shared
    let onCancel: () -> Void
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: model.compact ? 4 : 6) {
            ToolbarButton(symbol: "xmark", title: L("Отмена"), compact: model.compact, action: onCancel)
                .help(L("Отмена (Esc)"))
            separator
            ToolbarButton(symbol: "display", title: L("Весь экран"), compact: model.compact,
                          selected: settings.area == .fullScreen) { settings.area = .fullScreen }
                .help(L("Записать весь экран"))
            ToolbarButton(symbol: "rectangle.dashed", title: L("Область"), compact: model.compact,
                          selected: settings.area == .area) { settings.area = .area }
                .help(L("Записать выделенную область"))
            separator
            ToolbarButton(symbol: settings.recordSystemAudio ? "speaker.wave.2.fill" : "speaker.slash",
                          title: L("Звук"), compact: model.compact, selected: settings.recordSystemAudio) {
                settings.recordSystemAudio.toggle()
            }
            .help(settings.recordSystemAudio ? L("Системный звук записывается") : L("Системный звук не записывается"))
            ToolbarButton(symbol: settings.recordMicrophone ? "mic.fill" : "mic.slash",
                          title: L("Микрофон"), compact: model.compact, selected: settings.recordMicrophone) {
                settings.recordMicrophone.toggle()
            }
            .help(settings.recordMicrophone ? L("Микрофон записывается") : L("Микрофон не записывается"))
            ToolbarButton(symbol: settings.showCursor ? "cursorarrow" : "cursorarrow.slash",
                          title: L("Курсор"), compact: model.compact, selected: settings.showCursor) {
                settings.showCursor.toggle()
            }
            .help(settings.showCursor ? L("Курсор виден на записи") : L("Курсор скрыт на записи"))
            separator
            Button(action: onStart) {
                Label(model.compact ? "" : L("Записать"), systemImage: "record.circle.fill")
                    .labelStyle(model.compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, model.compact ? 12 : 16)
                    .frame(height: 38)
                    .background(Capsule().fill(model.canStart ? Color.red : Color.gray.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .disabled(!model.canStart)
            .help(model.canStart ? L("Начать запись (↩)") : L("Сначала выделите область"))
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .fixedSize()
    }

    private var separator: some View {
        Divider().frame(height: 30).padding(.horizontal, 2)
    }
}

struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

struct ToolbarButton: View {
    let symbol: String
    let title: String
    var compact = false
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    static let activeGradient = LinearGradient(
        colors: [Color(nsColor: .dynamic(light: 0x5B3CF5, dark: 0x9D8BFF)),
                 Color(nsColor: .dynamic(light: 0xC2257D, dark: 0xFF7AC6))],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 16 : 17, weight: selected ? .semibold : .regular))
                    .frame(height: 19)
                if !compact {
                    Text(title)
                        .font(.system(size: 10.5, weight: selected ? .bold : .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(Self.activeGradient)
                                      : AnyShapeStyle(Color.secondary.opacity(hovering ? 1 : 0.8)))
            .frame(minWidth: compact ? 34 : 62, minHeight: 38)
            .scaleEffect(hovering ? 1.06 : 1)
            .animation(.spring(duration: 0.2), value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension NSColor {
    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}
