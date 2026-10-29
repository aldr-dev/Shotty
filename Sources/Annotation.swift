import AppKit

enum Tool: String, CaseIterable, Identifiable {
    case select, arrow, rectangle, text, highlighter, emoji, blur, pixelate

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .text: "textformat"
        case .highlighter: "highlighter"
        case .emoji: "face.smiling"
        case .blur: "drop.halffull"
        case .pixelate: "squareshape.split.3x3"
        }
    }

    var title: String {
        switch self {
        case .select: L("Выбор и перемещение (V)")
        case .arrow: L("Стрелка (A)")
        case .rectangle: L("Цветная рамка (R)")
        case .text: L("Текст (T)")
        case .highlighter: L("Маркер (H)")
        case .emoji: L("Эмодзи — растягивается за ручки (E)")
        case .blur: L("Размытие — скрыть пароли, почту, токены (B)")
        case .pixelate: L("Пикселизация — скрыть пароли, почту, токены (P)")
        }
    }

    var shortcut: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .rectangle: "r"
        case .text: "t"
        case .highlighter: "h"
        case .emoji: "e"
        case .blur: "b"
        case .pixelate: "p"
        }
    }

    var kind: Annotation.Kind? {
        switch self {
        case .select: nil
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .text: .text
        case .highlighter: .highlighter
        case .emoji: .emoji
        case .blur: .blur
        case .pixelate: .pixelate
        }
    }
}

struct Annotation: Identifiable {
    enum Kind {
        case arrow, rectangle, text, highlighter, emoji, blur, pixelate

        /// Redactions alter the screenshot itself, so the canvas renders them from the source pixels.
        var isRedaction: Bool { self == .blur || self == .pixelate }
    }

    var id = UUID()
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
    var text: String = ""
    /// Clockwise turn around the box center, in radians. Only emoji can be rotated.
    var rotation: CGFloat = 0

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    var fontSize: CGFloat { Annotation.fontSize(for: lineWidth) }

    static func fontSize(for lineWidth: CGFloat) -> CGFloat { 10 + lineWidth * 2.5 }

    static func font(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: size) {
            return rounded
        }
        return base
    }

    var bounds: CGRect {
        switch kind {
        case .text:
            return CGRect(origin: start, size: attributedText().size())
        case .arrow:
            return rect.insetBy(dx: -lineWidth * 3, dy: -lineWidth * 3)
        case .rectangle, .highlighter:
            return rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case .blur, .pixelate:
            return rect
        case .emoji:
            return rect.applying(rotationTransform)
        }
    }

    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    /// Maps the unrotated box onto the canvas.
    var rotationTransform: CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation).translatedBy(x: -center.x, y: -center.y)
    }

    func toLocal(_ p: CGPoint) -> CGPoint { p.applying(rotationTransform.inverted()) }

    /// Distance of the rotation handle above the box's top edge, in canvas points at 100% zoom.
    static let rotationHandleOffset: CGFloat = 26

    func hitTest(_ p: CGPoint) -> Bool {
        let tolerance = max(lineWidth, 4) + 5
        switch kind {
        case .text, .highlighter, .blur, .pixelate:
            return bounds.insetBy(dx: -4, dy: -4).contains(p)
        case .emoji:
            return rect.insetBy(dx: -4, dy: -4).contains(toLocal(p))
        case .rectangle:
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            return outer.contains(p) && (inner.isNull || inner.isEmpty || !inner.contains(p))
        case .arrow:
            return distance(from: p, toSegment: start, end) <= tolerance
        }
    }

    mutating func offset(by d: CGSize) {
        start.x += d.width; start.y += d.height
        end.x += d.width; end.y += d.height
    }

    // MARK: Resizing

    enum Handle: CaseIterable {
        case start, end, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, rotate
    }

    /// Grab points shown on the selected annotation: arrow ends, or the eight points of a box.
    /// Text has none — its size follows the line-width slider.
    /// `zoom` keeps the rotation handle the same distance from the box on screen.
    func handles(zoom: CGFloat = 1) -> [(handle: Handle, point: CGPoint)] {
        let r = rect
        switch kind {
        case .text: return []
        case .arrow: return [(.start, start), (.end, end)]
        case .emoji:
            let box: [(Handle, CGPoint)] = [
                (.topLeft, CGPoint(x: r.minX, y: r.minY)), (.top, CGPoint(x: r.midX, y: r.minY)),
                (.topRight, CGPoint(x: r.maxX, y: r.minY)), (.right, CGPoint(x: r.maxX, y: r.midY)),
                (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)), (.bottom, CGPoint(x: r.midX, y: r.maxY)),
                (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.left, CGPoint(x: r.minX, y: r.midY)),
                (.rotate, CGPoint(x: r.midX, y: r.minY - Annotation.rotationHandleOffset / zoom)),
            ]
            return box.map { ($0.0, $0.1.applying(rotationTransform)) }
        case .rectangle, .highlighter, .blur, .pixelate:
            return [
                (.topLeft, CGPoint(x: r.minX, y: r.minY)), (.top, CGPoint(x: r.midX, y: r.minY)),
                (.topRight, CGPoint(x: r.maxX, y: r.minY)), (.right, CGPoint(x: r.maxX, y: r.midY)),
                (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)), (.bottom, CGPoint(x: r.midX, y: r.maxY)),
                (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.left, CGPoint(x: r.minX, y: r.midY)),
            ]
        }
    }

    /// `original` with `handle` dragged to `p`; edges may cross, which just flips the box.
    /// `keepAspect` (Shift) keeps a box's proportions when a corner is dragged.
    static func resized(_ original: Annotation, handle: Handle, to p: CGPoint, keepAspect: Bool) -> Annotation {
        var a = original
        if a.kind == .arrow {
            if handle == .start { a.start = p } else if handle == .end { a.end = p }
            return a
        }
        // Resize in the box's own unrotated frame, then put the new center back where it belongs.
        let p = original.toLocal(p)
        let r = original.rect
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch handle {
        case .topLeft: minX = p.x; minY = p.y
        case .top: minY = p.y
        case .topRight: maxX = p.x; minY = p.y
        case .right: maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y
        case .bottom: maxY = p.y
        case .bottomLeft: minX = p.x; maxY = p.y
        case .left: minX = p.x
        case .start, .end, .rotate: break
        }
        if keepAspect, r.width > 0, r.height > 0, [.topLeft, .topRight, .bottomRight, .bottomLeft].contains(handle) {
            // Scale by the larger of the two drag factors, anchored at the opposite corner.
            let scale = max(abs(maxX - minX) / r.width, abs(maxY - minY) / r.height)
            let w = r.width * scale, h = r.height * scale
            let anchorX = handle == .topLeft || handle == .bottomLeft ? r.maxX : r.minX
            let anchorY = handle == .topLeft || handle == .topRight ? r.maxY : r.minY
            let movingX = handle == .topLeft || handle == .bottomLeft ? minX : maxX
            let movingY = handle == .topLeft || handle == .topRight ? minY : maxY
            let x = anchorX + (movingX >= anchorX ? w : -w)
            let y = anchorY + (movingY >= anchorY ? h : -h)
            minX = anchorX; maxX = x; minY = anchorY; maxY = y
        }
        a.start = CGPoint(x: minX, y: minY)
        a.end = CGPoint(x: maxX, y: maxY)
        if original.rotation != 0 {
            let local = a.center, world = local.applying(original.rotationTransform)
            a.offset(by: CGSize(width: world.x - local.x, height: world.y - local.y))
        }
        return a
    }

    /// `original` turned so its top faces `p`; `snap` (Shift) rounds to 15° steps.
    static func rotated(_ original: Annotation, toward p: CGPoint, snap: Bool) -> Annotation {
        var a = original
        let c = original.center
        // The handle sits straight above the center, which is -90° in the flipped canvas.
        var angle = atan2(p.y - c.y, p.x - c.x) + .pi / 2
        if snap { angle = (angle / (.pi / 12)).rounded() * (.pi / 12) }
        angle = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if angle < 0 { angle += 2 * .pi }
        a.rotation = abs(angle - 2 * .pi) < 0.0001 ? 0 : angle
        return a
    }

    // MARK: Drawing (expects a flipped context)

    func draw() {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        switch kind {
        case .arrow: drawArrow(cg)
        case .rectangle: drawRectangle(cg)
        case .text: drawText(cg)
        case .highlighter: drawHighlighter(cg)
        case .emoji: drawEmoji(cg)
        case .blur, .pixelate: break // drawn by Redactor
        }
    }

    private func withShadow(_ cg: CGContext, _ body: () -> Void) {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 5,
                     color: NSColor.black.withAlphaComponent(0.35).cgColor)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    private func drawArrow(_ cg: CGContext) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }
        let ux = dx / length, uy = dy / length
        let headLength = min(max(lineWidth * 3.6, 14), length)
        let halfWidth = headLength * 0.5
        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let shaftEnd = CGPoint(x: end.x - ux * headLength * 0.7, y: end.y - uy * headLength * 0.7)

        withShadow(cg) {
            color.setStroke()
            color.setFill()
            let shaft = NSBezierPath()
            shaft.lineWidth = lineWidth
            shaft.lineCapStyle = .round
            shaft.move(to: start)
            shaft.line(to: shaftEnd)
            shaft.stroke()

            let head = NSBezierPath()
            head.move(to: end)
            head.line(to: CGPoint(x: base.x - uy * halfWidth, y: base.y + ux * halfWidth))
            head.line(to: CGPoint(x: base.x + uy * halfWidth, y: base.y - ux * halfWidth))
            head.close()
            head.lineJoinStyle = .round
            head.lineWidth = max(lineWidth * 0.4, 1)
            head.fill()
            head.stroke()
        }
    }

    private func drawRectangle(_ cg: CGContext) {
        guard rect.width > 0.5 || rect.height > 0.5 else { return }
        withShadow(cg) {
            let radius = min(6, min(rect.width, rect.height) / 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            path.lineWidth = lineWidth
            color.setStroke()
            path.stroke()
        }
    }

    /// Stretches the emoji's ink to fill `rect` exactly, so the box can be resized in any direction.
    private func drawEmoji(_ cg: CGContext) {
        let r = rect
        guard r.width > 1, r.height > 1, !text.isEmpty else { return }
        // Render near the final size so Apple Color Emoji picks a sharp bitmap strike.
        let fontSize = min(max(r.width, r.height), 512)
        let font = NSFont(name: "Apple Color Emoji", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        cg.saveGState()
        cg.concatenate(rotationTransform)
        cg.textMatrix = .identity
        let ink = CTLineGetImageBounds(line, cg)
        guard ink.width > 0, ink.height > 0 else { cg.restoreGState(); return }
        // The canvas is flipped; text wants y up, so flip around the box's bottom edge.
        cg.translateBy(x: r.minX, y: r.maxY)
        cg.scaleBy(x: r.width / ink.width, y: -r.height / ink.height)
        cg.translateBy(x: -ink.minX, y: -ink.minY)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }

    private func drawHighlighter(_ cg: CGContext) {
        cg.saveGState()
        cg.setBlendMode(.multiply)
        color.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        cg.restoreGState()
    }

    func attributedText(outline: Bool = false) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [.font: Annotation.font(size: fontSize)]
        if outline {
            attrs[.strokeColor] = outlineColor
            attrs[.strokeWidth] = 22
        } else {
            attrs[.foregroundColor] = color
        }
        return NSAttributedString(string: text, attributes: attrs)
    }

    private var outlineColor: NSColor {
        let c = color.usingColorSpace(.sRGB) ?? color
        let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luminance > 0.65 ? NSColor.black.withAlphaComponent(0.85) : .white
    }

    private func drawText(_ cg: CGContext) {
        withShadow(cg) {
            attributedText(outline: true).draw(at: start)
            attributedText().draw(at: start)
        }
    }
}

private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}
