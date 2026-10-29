import AppKit
import SwiftUI

/// Emoji grid shown from the editor's emoji tool, laid out like the system picker.
struct EmojiPickerView: View {
    @ObservedObject var model: EditorModel
    @State private var query = ""
    @State private var scrollRequest: EmojiGrid.ScrollRequest?
    private let recents = EmojiCatalog.recents
    private let categories = EmojiCatalog.categories

    private var sections: [EmojiGridView.Section] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return [EmojiGridView.Section(id: "search", title: nil, emojis: EmojiCatalog.search(trimmed))]
        }
        return [EmojiGridView.Section(id: "recent", title: L("Недавние"), emojis: recents)]
            + categories.map { EmojiGridView.Section(id: $0.id, title: $0.title, emojis: $0.emojis) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(L("Поиск эмодзи"), text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            EmojiGrid(sections: sections, scrollRequest: scrollRequest, onPick: pick)
            Divider()
            HStack(spacing: 0) {
                tab(id: "recent", symbol: "clock", title: L("Недавние"))
                ForEach(categories) { tab(id: $0.id, symbol: $0.symbol, title: $0.title) }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .frame(width: 360, height: 400)
    }

    private func tab(id: String, symbol: String, title: String) -> some View {
        Button {
            query = ""
            scrollRequest = EmojiGrid.ScrollRequest(sectionID: id)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func pick(_ emoji: String) {
        EmojiCatalog.noteUsed(emoji)
        // A pick always means "place a new one"; it never changes an emoji already on the screenshot.
        model.emoji = emoji
        model.tool = .emoji
        model.canvas?.clearSelection()
        model.showEmojiPicker = false
    }
}

struct EmojiGrid: NSViewRepresentable {
    /// Each tab click makes a new request, so clicking the same tab twice still scrolls.
    struct ScrollRequest: Equatable {
        let sectionID: String
        let token = UUID()
    }

    let sections: [EmojiGridView.Section]
    let scrollRequest: ScrollRequest?
    let onPick: (String) -> Void

    final class Coordinator { var handledRequest: ScrollRequest? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        let grid = EmojiGridView()
        grid.autoresizingMask = [.width]
        scroll.documentView = grid
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let grid = scroll.documentView as? EmojiGridView else { return }
        grid.onPick = onPick
        if grid.sections.map(\.emojis) != sections.map(\.emojis) {
            grid.sections = sections
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        if let request = scrollRequest, request != context.coordinator.handledRequest {
            context.coordinator.handledRequest = request
            DispatchQueue.main.async { grid.scrollToSection(request.sectionID) }
        }
    }
}

/// Draws the whole grid itself: only the visible rows are painted, each emoji glyph is rasterized
/// once and reused, and one tracking area covers hover for every cell.
final class EmojiGridView: NSView {
    struct Section {
        let id: String
        let title: String?
        let emojis: [String]
    }

    var sections: [Section] = [] { didSet { hovered = nil; relayout() } }
    var onPick: ((String) -> Void)?

    private let cell: CGFloat = 34, spacing: CGFloat = 2, columns = 9
    private let headerHeight: CGFloat = 24, sectionGap: CGFloat = 6, padding: CGFloat = 8
    private var sectionTops: [CGFloat] = []
    private struct Item: Equatable { let section: Int, index: Int }
    private var hovered: Item? { didSet { if oldValue != hovered { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    private var gridWidth: CGFloat { CGFloat(columns) * cell + CGFloat(columns - 1) * spacing }
    private var gridLeft: CGFloat { max(padding, (bounds.width - gridWidth) / 2) }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: newSize.width, height: contentHeight))
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        relayout()
    }

    private var contentHeight: CGFloat {
        var y: CGFloat = 0
        for section in sections { y += height(of: section) + sectionGap }
        return max(y + padding, superview?.bounds.height ?? 0)
    }

    private func height(of section: Section) -> CGFloat {
        let rows = (section.emojis.count + columns - 1) / columns
        return (section.title == nil ? 4 : headerHeight) + CGFloat(rows) * (cell + spacing)
    }

    private func relayout() {
        var y: CGFloat = 0
        sectionTops = sections.map { section in
            defer { y += height(of: section) + sectionGap }
            return y
        }
        setFrameSize(NSSize(width: superview?.bounds.width ?? bounds.width, height: 0))
        needsDisplay = true
    }

    func scrollToSection(_ id: String) {
        guard let i = sections.firstIndex(where: { $0.id == id }), let clip = enclosingScrollView?.contentView else { return }
        let maxY = max(bounds.height - clip.bounds.height, 0)
        clip.scroll(to: NSPoint(x: 0, y: min(sectionTops[i], maxY)))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    private func gridTop(_ s: Int) -> CGFloat {
        sectionTops[s] + (sections[s].title == nil ? 4 : headerHeight)
    }

    private func frame(section s: Int, index i: Int) -> CGRect {
        CGRect(x: gridLeft + CGFloat(i % columns) * (cell + spacing),
               y: gridTop(s) + CGFloat(i / columns) * (cell + spacing),
               width: cell, height: cell)
    }

    private func item(at p: CGPoint) -> Item? {
        for s in sections.indices.reversed() where p.y >= gridTop(s) {
            let col = Int((p.x - gridLeft) / (cell + spacing)), row = Int((p.y - gridTop(s)) / (cell + spacing))
            guard p.x >= gridLeft, col < columns, row >= 0 else { return nil }
            let index = row * columns + col
            guard index < sections[s].emojis.count, frame(section: s, index: index).contains(p) else { return nil }
            return Item(section: s, index: index)
        }
        return nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if sections.allSatisfy(\.emojis.isEmpty) {
            let text = NSAttributedString(string: L("Ничего не найдено"), attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor])
            let size = text.size()
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: 60))
            return
        }
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor]
        let scale = window?.backingScaleFactor ?? 2
        for (s, section) in sections.enumerated() {
            let top = sectionTops[s]
            guard top <= dirtyRect.maxY, top + height(of: section) >= dirtyRect.minY else { continue }
            if let title = section.title {
                (title as NSString).draw(at: NSPoint(x: gridLeft + 4, y: top + 6), withAttributes: headerAttrs)
            }
            let firstRow = max(0, Int((dirtyRect.minY - gridTop(s)) / (cell + spacing)))
            let lastRow = Int((dirtyRect.maxY - gridTop(s)) / (cell + spacing))
            guard lastRow >= firstRow else { continue }
            for i in (firstRow * columns)..<min((lastRow + 1) * columns, section.emojis.count) {
                let r = frame(section: s, index: i)
                if hovered == Item(section: s, index: i) {
                    NSColor.labelColor.withAlphaComponent(0.1).setFill()
                    NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
                }
                let image = EmojiGlyphCache.image(section.emojis[i], scale: scale)
                image.draw(in: CGRect(x: r.midX - image.size.width / 2, y: r.midY - image.size.height / 2,
                                      width: image.size.width, height: image.size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
    }

    // MARK: Mouse

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) { hovered = item(at: convert(event.locationInWindow, from: nil)) }

    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        hovered = window.map { item(at: convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? nil
    }

    override func mouseUp(with event: NSEvent) {
        guard let hit = item(at: convert(event.locationInWindow, from: nil)) else { return }
        onPick?(sections[hit.section].emojis[hit.index])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Rasterized 24 pt Apple Color Emoji glyphs, kept for the app's lifetime so reopening the picker is instant.
enum EmojiGlyphCache {
    private static var images: [String: NSImage] = [:]

    static func image(_ emoji: String, scale: CGFloat) -> NSImage {
        let key = "\(emoji)@\(scale)"
        if let cached = images[key] { return cached }
        let font = NSFont(name: "Apple Color Emoji", size: 24) ?? NSFont.systemFont(ofSize: 24)
        let text = NSAttributedString(string: emoji, attributes: [.font: font])
        let size = text.size()
        let image = NSImage(size: size)
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * scale)),
                                      pixelsHigh: Int(ceil(size.height * scale)), bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            // Setting the point size first makes the context draw at `scale` pixels per point.
            rep.size = size
            guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return image }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            text.draw(at: .zero)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        images[key] = image
        return image
    }
}
