import AppKit
import UniformTypeIdentifiers

final class CanvasView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    let image: NSImage
    private unowned let model: EditorModel

    var annotations: [Annotation] = [] { didSet { needsDisplay = true; refreshCursor() } }
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    private var current: Annotation?
    private var selectedID: UUID? { didSet { needsDisplay = true; lastStyleEdit = nil; refreshCursor() } }
    private var dragLast: CGPoint?
    private var dragPushedUndo = false
    /// Handle being dragged on the selected annotation, with the annotation as it was at mouse-down.
    private var resizing: (handle: Annotation.Handle, original: Annotation)?

    private var editingField: NSTextField?
    private var editingID: UUID?
    private var editingOrigin: CGPoint = .zero

    var onCopy: (() -> Void)?

    private lazy var redactor = Redactor(image: image)

    init(image: NSImage, model: EditorModel) {
        self.image = image
        self.model = model
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        renderContent(includeSelection: true)
    }

    private func renderContent(includeSelection: Bool) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        let visible = annotations.filter { $0.id != editingID } + (current.map { [$0] } ?? [])
        // Redactions go first so arrows and labels drawn on top of them stay readable.
        for annotation in visible where annotation.kind.isRedaction {
            redactor.draw(annotation)
        }
        for annotation in visible where !annotation.kind.isRedaction {
            annotation.draw()
        }

        if includeSelection, let a = selected {
            let scale = 1 / magnification
            let handles = a.handles(zoom: magnification)
            if a.kind == .emoji {
                // Box and rotation stick follow the emoji's turn.
                let path = NSBezierPath(rect: a.rect)
                let top = CGPoint(x: a.rect.midX, y: a.rect.minY)
                path.move(to: top)
                path.line(to: CGPoint(x: top.x, y: top.y - Annotation.rotationHandleOffset * scale))
                let t = NSAffineTransform()
                t.transformStruct = NSAffineTransformStruct(m11: a.rotationTransform.a, m12: a.rotationTransform.b,
                                                            m21: a.rotationTransform.c, m22: a.rotationTransform.d,
                                                            tX: a.rotationTransform.tx, tY: a.rotationTransform.ty)
                path.transform(using: t as AffineTransform)
                path.lineWidth = 1 * scale
                NSColor.controlAccentColor.setStroke()
                path.stroke()
            } else if handles.isEmpty || a.kind == .arrow {
                let path = NSBezierPath(roundedRect: a.bounds.insetBy(dx: -5, dy: -5), xRadius: 4, yRadius: 4)
                path.lineWidth = 1.5 * scale
                path.setLineDash([5 * scale, 4 * scale], count: 2, phase: 0)
                NSColor.controlAccentColor.setStroke()
                path.stroke()
            } else {
                let path = NSBezierPath(rect: a.rect)
                path.lineWidth = 1 * scale
                NSColor.controlAccentColor.setStroke()
                path.stroke()
            }
            // Handles keep the same on-screen size at any zoom.
            let side = 8 * scale
            for (handle, p) in handles {
                let frame = CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)
                let square = handle == .rotate
                    ? NSBezierPath(ovalIn: frame.insetBy(dx: -1.5 * scale, dy: -1.5 * scale))
                    : NSBezierPath(roundedRect: frame, xRadius: 2 * scale, yRadius: 2 * scale)
                NSColor.white.setFill()
                square.fill()
                square.lineWidth = 1.5 * scale
                NSColor.controlAccentColor.setStroke()
                square.stroke()
            }
        }
    }

    private var selected: Annotation? {
        guard let id = selectedID else { return nil }
        return annotations.first { $0.id == id }
    }

    private var magnification: CGFloat { max(enclosingScrollView?.magnification ?? 1, 0.01) }

    private func handle(at p: CGPoint) -> Annotation.Handle? {
        guard let a = selected, model.tool == .select || a.kind == model.tool.kind else { return nil }
        let reach = 7 / magnification
        // Rotation is checked first: on a tiny emoji it can sit right next to the top handle.
        return a.handles(zoom: magnification).sorted { $0.handle == .rotate && $1.handle != .rotate }.first { abs($0.point.x - p.x) <= reach && abs($0.point.y - p.y) <= reach }?.handle
    }

    func renderedImage() -> NSImage {
        let pixelSize: NSSize
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pixelSize = NSSize(width: cg.width, height: cg.height)
        } else {
            pixelSize = image.size
        }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixelSize.width), pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return image }

        NSGraphicsContext.saveGraphicsState()
        let cg = ctx.cgContext
        cg.scaleBy(x: pixelSize.width / image.size.width, y: pixelSize.height / image.size.height)
        cg.translateBy(x: 0, y: image.size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        renderContent(includeSelection: false)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = image.size

        let result = NSImage(size: image.size)
        result.addRepresentation(rep)
        return result
    }

    func pngData() -> Data? {
        let img = renderedImage()
        guard let rep = img.representations.first as? NSBitmapImageRep else { return nil }
        return Self.optimizedPNG(rep) ?? rep.representation(using: .png, properties: [:])
    }

    /// Lossless PNG: drops the alpha channel when nothing is transparent (window captures keep their
    /// shadow) and lets the encoder try every row filter. Pixels stay exactly the same.
    static func optimizedPNG(_ rep: NSBitmapImageRep) -> Data? {
        guard var image = rep.cgImage else { return nil }
        if isOpaque(rep), let colorSpace = image.colorSpace,
           let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                               bytesPerRow: 0, space: colorSpace,
                               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            if let opaque = ctx.makeImage() { image = opaque }
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        // Keep the Retina density so the file opens at its on-screen size.
        let dpi = 72 * CGFloat(rep.pixelsWide) / max(rep.size.width, 1)
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
            // IMAGEIO_PNG_ALL_FILTERS (none|sub|up|avg|paeth); the C macro isn't visible from Swift.
            kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGCompressionFilter: 0xF8],
        ]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    private static func isOpaque(_ rep: NSBitmapImageRep) -> Bool {
        guard rep.hasAlpha else { return true }
        guard rep.samplesPerPixel == 4, rep.bitsPerSample == 8, !rep.isPlanar,
              !rep.bitmapFormat.contains(.alphaFirst), let bytes = rep.bitmapData else { return false }
        for y in 0..<rep.pixelsHigh {
            let row = bytes + y * rep.bytesPerRow
            for x in 0..<rep.pixelsWide where row[x * 4 + 3] != 255 { return false }
        }
        return true
    }

    func jpegData() -> Data? {
        let img = renderedImage()
        guard let rep = img.representations.first as? NSBitmapImageRep else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    // MARK: Cursor

    // Cursor rects can't express per-handle cursors, so the cursor follows a tracking area instead.
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { cursor(at: point(for: event)).set() }

    override func mouseMoved(with event: NSEvent) { cursor(at: point(for: event)).set() }

    private func refreshCursor() {
        guard let window, resizing == nil, dragLast == nil else { return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(p) else { return }
        cursor(at: p).set()
    }

    private func cursor(at p: CGPoint) -> NSCursor {
        if let handle = handle(at: p) {
            let position: NSCursor.FrameResizePosition
            switch handle {
            case .start, .end: return .crosshair
            case .rotate: return Self.rotateCursor
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .right: position = .right
            case .bottomRight: position = .bottomRight
            case .bottom: position = .bottom
            case .bottomLeft: position = .bottomLeft
            case .left: position = .left
            }
            return .frameResize(position: position, directions: .all)
        }
        switch model.tool {
        case .select: return .arrow
        case .text: return .iBeam
        case .emoji: return topmost(at: p, kind: .emoji) != nil ? .openHand : .crosshair
        default: return .crosshair
        }
    }

    func toolDidChange() {
        commitTextEditing()
        if model.tool != .select, selected?.kind != model.tool.kind { selectedID = nil }
        refreshCursor()
    }

    private static let rotateCursor: NSCursor = {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return .crosshair }
        // White halo under a black glyph, so the cursor reads on any screenshot.
        let size = NSSize(width: symbol.size.width + 4, height: symbol.size.height + 4)
        let image = NSImage(size: size, flipped: false) { rect in
            let glyph = { (color: NSColor) -> NSImage in
                let tinted = symbol.copy() as! NSImage
                tinted.lockFocus()
                color.set()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                return tinted
            }
            let white = glyph(.white), black = glyph(.black)
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)] {
                white.draw(at: NSPoint(x: 2 + CGFloat(dx), y: 2 + CGFloat(dy)), from: .zero, operation: .sourceOver, fraction: 1)
            }
            black.draw(at: NSPoint(x: 2, y: 2), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()

    func clearSelection() { selectedID = nil }

    private var defaultEmojiSide: CGFloat {
        min(max(min(bounds.width, bounds.height) * 0.12, 48), 160)
    }

    enum StyleProperty { case color, lineWidth }

    func styleDidChange(_ property: StyleProperty) {
        if let field = editingField {
            field.textColor = model.color
            field.font = Annotation.font(size: Annotation.fontSize(for: model.lineWidth))
            resizeEditingField()
        }
        guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        // A slider drag or color-picker drag fires many changes; keep them as one undo step.
        if lastStyleEdit?.id != id || lastStyleEdit?.property != property {
            pushUndo()
            lastStyleEdit = (id, property)
        }
        annotations[index].color = model.color
        annotations[index].lineWidth = model.lineWidth
    }

    // MARK: Undo

    /// The style change that the latest undo step covers; nil once anything else happens.
    private var lastStyleEdit: (id: UUID, property: StyleProperty)?

    private func pushUndo() {
        lastStyleEdit = nil
        undoStack.append(annotations)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        syncHistoryState()
    }

    private func syncHistoryState() {
        model.canUndo = !undoStack.isEmpty
        model.canRedo = !redoStack.isEmpty
    }

    @objc func undo(_ sender: Any?) {
        commitTextEditing()
        guard let previous = undoStack.popLast() else { return }
        lastStyleEdit = nil
        redoStack.append(annotations)
        annotations = previous
        selectedID = nil
        syncHistoryState()
    }

    @objc func redo(_ sender: Any?) {
        guard let next = redoStack.popLast() else { return }
        lastStyleEdit = nil
        undoStack.append(annotations)
        annotations = next
        selectedID = nil
        syncHistoryState()
    }

    @objc func copy(_ sender: Any?) { onCopy?() }

    @objc func delete(_ sender: Any?) { deleteSelection() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): return !undoStack.isEmpty
        case #selector(redo(_:)): return !redoStack.isEmpty
        case #selector(delete(_:)): return selectedID != nil
        default: return true
        }
    }

    private func deleteSelection() {
        guard let id = selectedID else { return }
        pushUndo()
        annotations.removeAll { $0.id == id }
        selectedID = nil
    }

    // MARK: Mouse

    private func point(for event: NSEvent) -> CGPoint {
        let p = unclampedPoint(for: event)
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    /// The rotation handle can stick out past the screenshot's edge, so handles use the raw point.
    private func unclampedPoint(for event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    private func topmost(at p: CGPoint, kind: Annotation.Kind? = nil) -> Annotation? {
        annotations.reversed().first { (kind == nil || $0.kind == kind) && $0.hitTest(p) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(for: event)
        if editingField != nil {
            commitTextEditing()
            if model.tool == .text { return }
        }
        window?.makeFirstResponder(self)

        if let handle = handle(at: unclampedPoint(for: event)), let a = selected {
            if handle == .rotate, event.clickCount == 2, let index = annotations.firstIndex(where: { $0.id == a.id }) {
                pushUndo()
                annotations[index].rotation = 0
                return
            }
            resizing = (handle, a)
            dragPushedUndo = false
            return
        }

        switch model.tool {
        case .emoji:
            if let hit = topmost(at: p, kind: .emoji) {
                selectedID = hit.id
                dragLast = p
                dragPushedUndo = false
                NSCursor.closedHand.set()
            } else {
                selectedID = nil
                current = Annotation(kind: .emoji, start: p, end: p, color: model.color,
                                     lineWidth: model.lineWidth, text: model.emoji)
            }
        case .select:
            if let hit = topmost(at: p) {
                selectedID = hit.id
                if event.clickCount == 2, hit.kind == .text {
                    beginTextEditing(existing: hit)
                    return
                }
                dragLast = p
                dragPushedUndo = false
            } else {
                selectedID = nil
            }
        case .text:
            if let hit = topmost(at: p, kind: .text) {
                beginTextEditing(existing: hit)
            } else {
                beginTextEditing(at: p)
            }
        default:
            guard let kind = model.tool.kind else { return }
            current = Annotation(kind: kind, start: p, end: p, color: model.color, lineWidth: model.lineWidth)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(for: event)
        if let (handle, original) = resizing, let index = annotations.firstIndex(where: { $0.id == original.id }) {
            if !dragPushedUndo { pushUndo(); dragPushedUndo = true }
            let shift = event.modifierFlags.contains(.shift)
            annotations[index] = handle == .rotate
                ? Annotation.rotated(original, toward: unclampedPoint(for: event), snap: shift)
                : Annotation.resized(original, handle: handle, to: p, keepAspect: shift)
        } else if var drawing = current {
            drawing.end = event.modifierFlags.contains(.shift) ? constrained(from: drawing.start, to: p, kind: drawing.kind) : p
            current = drawing
            needsDisplay = true
        } else if let last = dragLast, let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }) {
            if !dragPushedUndo { pushUndo(); dragPushedUndo = true }
            annotations[index].offset(by: CGSize(width: p.x - last.x, height: p.y - last.y))
            dragLast = p
        }
    }

    override func mouseUp(with event: NSEvent) {
        if var drawing = current {
            current = nil
            let dragged = hypot(drawing.end.x - drawing.start.x, drawing.end.y - drawing.start.y) > 3
            if drawing.kind == .emoji {
                // A click jitters by a few pixels, and at reduced zoom that's many canvas points;
                // only a box clearly bigger than that counts as "drawn to size".
                let drawnToSize = max(drawing.rect.width, drawing.rect.height) * magnification >= 24
                if !drawnToSize {
                    let side = defaultEmojiSide
                    drawing.start = CGPoint(x: drawing.start.x - side / 2, y: drawing.start.y - side / 2)
                    drawing.end = CGPoint(x: drawing.start.x + side, y: drawing.start.y + side)
                }
                pushUndo()
                annotations.append(drawing)
                selectedID = drawing.id
                EmojiCatalog.noteUsed(drawing.text)
                // One pick places one emoji: switch to Select so the next click only moves or deselects.
                // Picking from the list again places another.
                model.tool = .select
            } else if dragged {
                pushUndo()
                annotations.append(drawing)
            }
            needsDisplay = true
        }
        if let (_, original) = resizing, let index = annotations.firstIndex(where: { $0.id == original.id }) {
            // Store the box normalized so later handle drags start from the visible corners.
            // An emoji squashed to nothing couldn't be seen or grabbed again.
            var r = annotations[index].rect
            if annotations[index].kind == .emoji {
                r = r.insetBy(dx: min(r.width - 12, 0) / 2, dy: min(r.height - 12, 0) / 2)
            }
            annotations[index].start = r.origin
            annotations[index].end = CGPoint(x: r.maxX, y: r.maxY)
        }
        resizing = nil
        dragLast = nil
        refreshCursor()
    }

    private func constrained(from s: CGPoint, to p: CGPoint, kind: Annotation.Kind) -> CGPoint {
        let dx = p.x - s.x, dy = p.y - s.y
        if kind == .arrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: s.x + cos(angle) * length, y: s.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: s.x + (dx < 0 ? -side : side), y: s.y + (dy < 0 ? -side : side))
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        switch event.keyCode {
        case 51, 117:
            deleteSelection()
            return
        case 53:
            selectedID = nil
            return
        case 123, 124, 125, 126:
            // Arrows nudge the selection by 1 pt, with Shift by 10 pt.
            guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }) else { break }
            let step: CGFloat = mods.contains(.shift) ? 10 : 1
            let d: CGSize = switch event.keyCode {
            case 123: CGSize(width: -step, height: 0)
            case 124: CGSize(width: step, height: 0)
            case 125: CGSize(width: 0, height: step)
            default: CGSize(width: 0, height: -step)
            }
            if !event.isARepeat || undoStack.isEmpty { pushUndo() }
            annotations[index].offset(by: d)
            return
        default:
            break
        }
        if mods.isEmpty, let chars = event.charactersIgnoringModifiers?.lowercased(),
           let tool = Tool.allCases.first(where: { $0.shortcut == chars || cyrillicShortcut(chars) == $0.shortcut }) {
            model.tool = tool
            if tool == .emoji { model.showEmojiPicker = true }
            return
        }
        super.keyDown(with: event)
    }

    private func cyrillicShortcut(_ c: String) -> String? {
        ["м": "v", "ф": "a", "к": "r", "е": "t", "р": "h", "у": "e", "и": "b", "з": "p"][c]
    }

    // MARK: Text editing

    private func beginTextEditing(at p: CGPoint) {
        editingID = nil
        editingOrigin = p
        showField(text: "", color: model.color, lineWidth: model.lineWidth)
    }

    private func beginTextEditing(existing a: Annotation) {
        editingID = a.id
        editingOrigin = a.start
        selectedID = nil
        showField(text: a.text, color: a.color, lineWidth: a.lineWidth)
        needsDisplay = true
    }

    private func showField(text: String, color: NSColor, lineWidth: CGFloat) {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.85)
        field.textColor = color
        field.font = Annotation.font(size: Annotation.fontSize(for: lineWidth))
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.placeholderString = L("Текст")
        editingField = field
        addSubview(field)
        resizeEditingField()
        window?.makeFirstResponder(field)
    }

    private func resizeEditingField() {
        guard let field = editingField, let font = field.font else { return }
        let text = field.stringValue.isEmpty ? L("Текст") : field.stringValue
        let size = (text as NSString).size(withAttributes: [.font: font])
        field.frame = NSRect(x: editingOrigin.x - 2, y: editingOrigin.y,
                             width: max(size.width + 24, 60), height: ceil(size.height) + 2)
    }

    func controlTextDidChange(_ obj: Notification) { resizeEditingField() }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === editingField else { return }
        commitTextEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(cancelOperation(_:)) {
            cancelTextEditing()
            return true
        }
        return false
    }

    func commitTextEditing() {
        guard let field = editingField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = field.textColor ?? model.color
        editingField = nil
        field.removeFromSuperview()

        if let id = editingID, let index = annotations.firstIndex(where: { $0.id == id }) {
            pushUndo()
            if text.isEmpty {
                annotations.remove(at: index)
            } else {
                annotations[index].text = text
                annotations[index].color = color
            }
        } else if !text.isEmpty {
            pushUndo()
            annotations.append(Annotation(kind: .text, start: editingOrigin, end: editingOrigin,
                                          color: color, lineWidth: model.lineWidth, text: text))
        }
        editingID = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func cancelTextEditing() {
        guard let field = editingField else { return }
        editingField = nil
        field.removeFromSuperview()
        editingID = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}

final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width { rect.origin.x = (doc.frame.width - rect.width) / 2 }
        if rect.height > doc.frame.height { rect.origin.y = (doc.frame.height - rect.height) / 2 }
        return rect
    }
}
