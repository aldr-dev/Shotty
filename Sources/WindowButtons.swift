import AppKit

/// macOS greys out the close/minimize/zoom buttons of every window that isn't key.
/// This swaps them for look-alikes that keep their colors regardless of focus.
enum WindowButtons {
    private static var key: UInt8 = 0

    static func keepColored(_ window: NSWindow) {
        guard objc_getAssociatedObject(window, &key) == nil,
              let close = window.standardWindowButton(.closeButton),
              let container = close.superview else { return }
        let originals = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { type in window.standardWindowButton(type).map { (type, $0) } }
        let frame = originals.map(\.1.frame).reduce(originals[0].1.frame) { $0.union($1) }
        let group = TrafficLightGroup(frame: frame, window: window, originals: originals)
        group.autoresizingMask = [.maxXMargin, .minYMargin]
        container.addSubview(group)
        originals.forEach { $0.1.isHidden = true }
        objc_setAssociatedObject(window, &key, group, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private final class TrafficLightGroup: NSView {
    private var hovering = false { didSet { lights.forEach { $0.showsGlyph = hovering } } }
    private var lights: [TrafficLight] = []
    private var observations: [NSKeyValueObservation] = []

    init(frame: NSRect, window: NSWindow, originals: [(NSWindow.ButtonType, NSButton)]) {
        super.init(frame: frame)
        for (type, original) in originals {
            let light = TrafficLight(type: type, original: original, window: window)
            light.frame = original.frame.offsetBy(dx: -frame.minX, dy: -frame.minY)
            addSubview(light)
            lights.append(light)
            // Windows disable their close button while uploading — mirror that.
            observations.append(original.observe(\.isEnabled) { [weak light] _, _ in
                light?.needsDisplay = true
                light.map { $0.window?.invalidateCursorRects(for: $0) }
            })
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
}

private final class TrafficLight: NSView {
    let type: NSWindow.ButtonType
    weak var original: NSButton?
    weak var targetWindow: NSWindow?
    var showsGlyph = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    init(type: NSWindow.ButtonType, original: NSButton, window: NSWindow) {
        self.type = type
        self.original = original
        self.targetWindow = window
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isEnabled: Bool { original?.isEnabled ?? false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        pressed = false
        guard bounds.contains(convert(event.locationInWindow, from: nil)), let window = targetWindow else { return }
        switch type {
        case .closeButton: window.performClose(nil)
        case .miniaturizeButton: window.performMiniaturize(nil)
        case .zoomButton: window.toggleFullScreen(nil)
        default: break
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let diameter: CGFloat = 12
        let circle = NSRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
        let path = NSBezierPath(ovalIn: circle.insetBy(dx: 0.25, dy: 0.25))

        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let (fill, stroke): (NSColor, NSColor) = {
            guard isEnabled else {
                return dark ? (NSColor(white: 1, alpha: 0.18), NSColor(white: 1, alpha: 0.08))
                            : (NSColor(white: 0, alpha: 0.12), NSColor(white: 0, alpha: 0.06))
            }
            switch type {
            case .closeButton: return (rgb(0xFF5F57), rgb(0xE0443E))
            case .miniaturizeButton: return (rgb(0xFEBC2E), rgb(0xDEA123))
            default: return (rgb(0x28C840), rgb(0x1AAB29))
            }
        }()
        (pressed ? fill.blended(withFraction: 0.25, of: .black) ?? fill : fill).setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        guard showsGlyph, isEnabled else { return }
        let c = NSPoint(x: circle.midX, y: circle.midY)
        NSColor(white: 0, alpha: 0.5).set()
        let glyph = NSBezierPath()
        glyph.lineWidth = 1.2
        glyph.lineCapStyle = .round
        switch type {
        case .closeButton:
            let d: CGFloat = 2.6
            glyph.move(to: NSPoint(x: c.x - d, y: c.y - d)); glyph.line(to: NSPoint(x: c.x + d, y: c.y + d))
            glyph.move(to: NSPoint(x: c.x - d, y: c.y + d)); glyph.line(to: NSPoint(x: c.x + d, y: c.y - d))
            glyph.stroke()
        case .miniaturizeButton:
            glyph.move(to: NSPoint(x: c.x - 3.4, y: c.y)); glyph.line(to: NSPoint(x: c.x + 3.4, y: c.y))
            glyph.stroke()
        default:
            // Two opposing triangles, as on the full-screen button
            let a = NSBezierPath()
            a.move(to: NSPoint(x: c.x - 3.2, y: c.y + 3.2))
            a.line(to: NSPoint(x: c.x + 1.2, y: c.y + 3.2))
            a.line(to: NSPoint(x: c.x - 3.2, y: c.y - 1.2))
            a.close()
            a.fill()
            let b = NSBezierPath()
            b.move(to: NSPoint(x: c.x + 3.2, y: c.y - 3.2))
            b.line(to: NSPoint(x: c.x - 1.2, y: c.y - 3.2))
            b.line(to: NSPoint(x: c.x + 3.2, y: c.y + 1.2))
            b.close()
            b.fill()
        }
    }

    private func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
