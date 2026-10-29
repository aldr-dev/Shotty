import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct Toast: Equatable {
    var message: String
    var symbol: String
    var isError = false
}

final class EditorModel: ObservableObject {
    @Published var tool: Tool = .arrow { didSet { canvas?.toolDidChange() } }
    @Published var color: NSColor = .systemRed { didSet { canvas?.styleDidChange(.color) } }
    @Published var lineWidth: CGFloat = 4 { didSet { canvas?.styleDidChange(.lineWidth) } }
    @Published var emoji: String = EmojiCatalog.recents.first ?? "👍"
    @Published var showEmojiPicker = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var zoom: CGFloat = 1
    @Published var isUploading = false {
        didSet { controller?.window?.standardWindowButton(.closeButton)?.isEnabled = !isUploading }
    }
    @Published var toast: Toast?

    let imageSize: NSSize
    weak var canvas: CanvasView?
    weak var controller: EditorWindowController?

    static var colorNames: [String] { [L("Красный"), L("Оранжевый"), L("Жёлтый"), L("Зелёный"), L("Синий"), L("Фиолетовый"), L("Белый"), L("Чёрный")] }

    static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .white, .black,
    ]

    init(imageSize: NSSize) { self.imageSize = imageSize }

    func showToast(_ toast: Toast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + (toast.isError ? 6 : 3)) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: EditorModel
    let canvas: CanvasView
    private let scrollView = NSScrollView()
    var onClose: ((EditorWindowController) -> Void)?
    private let createdAt = Date()

    init(image: NSImage) {
        model = EditorModel(imageSize: image.size)
        canvas = CanvasView(image: image, model: model)

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(image.size.width + 80, 900), screen.width * 0.9)
        let height = min(max(image.size.height + 160, 560), screen.height * 0.9)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 760, height: 460)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.tabbingMode = .disallowed
        super.init(window: window)

        model.canvas = canvas
        model.controller = self
        canvas.onCopy = { [weak self] in self?.copyImage(nil) }

        window.title = "Shotty — " + Self.timestampFormatter.string(from: createdAt)
        window.delegate = self
        WindowButtons.keepColored(window)

        let clip = CenteringClipView()
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.borderType = .noBorder
        NotificationCenter.default.addObserver(self, selector: #selector(magnificationChanged),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)

        let hosting = NSHostingView(rootView: Localized {
            EditorContentView(model: model, scrollView: self.scrollView)
        })
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(canvas)
        DispatchQueue.main.async { [weak self] in self?.zoomToFit() }
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        onClose?(self)
    }

    // MARK: Zoom

    @objc private func magnificationChanged() { model.zoom = scrollView.magnification }

    func setZoom(_ value: CGFloat) {
        let z = min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
        let visible = scrollView.documentVisibleRect
        scrollView.setMagnification(z, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
        model.zoom = z
    }

    func zoomToFit() {
        let available = scrollView.contentSize
        let size = canvas.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let fit = min((available.width - 48) / size.width, (available.height - 48) / size.height, 1)
        setZoom(max(fit, 0.1))
    }

    // MARK: Actions

    private static var timestampFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = AppPreferences.shared.language.locale
        f.dateFormat = "d MMM yyyy, HH:mm:ss"
        return f
    }

    var defaultBaseName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "shotty_" + f.string(from: createdAt)
    }

    private var pngFileName: String { defaultBaseName + ".png" }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(uploadImage(_:)) || menuItem.action == #selector(saveImage(_:))
            || menuItem.action == #selector(NSWindow.performClose(_:)) {
            return !model.isUploading
        }
        return true
    }

    /// Closing mid-upload is blocked so the window can't disappear before the result is known.
    func windowShouldClose(_ sender: NSWindow) -> Bool { !model.isUploading }

    @objc func copyImage(_ sender: Any?) {
        canvas.commitTextEditing()
        guard let png = canvas.pngData() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        if let tiff = canvas.renderedImage().tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        model.showToast(Toast(message: L("Скопировано в буфер обмена"), symbol: "doc.on.doc.fill"))
    }

    @objc func saveImage(_ sender: Any?) {
        canvas.commitTextEditing()
        guard !model.isUploading, let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = pngFileName
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.isExtensionHidden = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let isJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
            guard let data = isJPEG ? self.canvas.jpegData() : self.canvas.pngData() else { return }
            do {
                try data.write(to: url)
                HUD.show(L("Сохранено: %@", url.lastPathComponent), symbol: "checkmark.circle.fill")
                self.close()
            } catch {
                self.model.showToast(Toast(message: error.localizedDescription, symbol: "exclamationmark.triangle.fill", isError: true))
            }
        }
    }

    @objc func uploadImage(_ sender: Any?) {
        canvas.commitTextEditing()
        guard !model.isUploading else { return }
        guard let config = ServerSettings.shared.activeConfig else {
            let alert = NSAlert()
            alert.messageText = L("Сервер не настроен")
            alert.informativeText = L("Укажите данные FTP или SFTP сервера в настройках.")
            alert.addButton(withTitle: L("Открыть настройки"))
            alert.addButton(withTitle: L("Отмена"))
            if let window {
                alert.beginSheetModal(for: window) { response in
                    if response == .alertFirstButtonReturn { AppDelegate.shared?.showSettings(tab: .server) }
                }
            }
            return
        }
        guard let data = canvas.pngData() else { return }
        let serverName = ServerSettings.shared.active?.displayName ?? config.host
        model.isUploading = true
        Task { @MainActor in
            do {
                let result = try await Uploader.upload(data: data, fileExtension: "png", config: config)
                self.model.isUploading = false
                if let link = result.link, ServerSettings.shared.copyLinkAfterUpload {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                    HUD.show(L("Загружено на «%@». Ссылка скопирована: %@", serverName, link), symbol: "checkmark.icloud.fill")
                } else {
                    HUD.show(L("Загружено на «%@»: %@", serverName, result.fileName), symbol: "checkmark.icloud.fill")
                }
                self.close()
            } catch {
                self.model.isUploading = false
                self.model.showToast(Toast(message: error.localizedDescription, symbol: "exclamationmark.icloud.fill", isError: true))
            }
        }
    }
}

// MARK: - SwiftUI

struct EditorContentView: View {
    @ObservedObject var model: EditorModel
    let scrollView: NSScrollView

    var body: some View {
        VStack(spacing: 0) {
            EditorTopBar(model: model)
            Divider()
            ViewHost(view: scrollView)
            Divider()
            StatusBar(model: model)
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
    }
}

struct EditorTopBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            ToolPicker(model: model)
            ViewThatFits(in: .horizontal) {
                StylePicker(model: model)
                CompactStylePicker(model: model)
            }
            Spacer(minLength: 8)
            HistoryButtons(model: model)
            ShareButtons(model: model)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .padding(.top, 2)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct CompactStylePicker: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(Array(EditorModel.palette.enumerated()), id: \.offset) { index, color in
                    Button {
                        model.color = color
                    } label: {
                        Label { Text(EditorModel.colorNames[index]) } icon: { Image(nsImage: NSImage.swatch(color, size: 14)) }
                    }
                }
            } label: {
                Image(nsImage: NSImage.swatch(model.color, size: 18))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .help(L("Цвет"))

            ColorPicker("", selection: Binding(
                get: { Color(nsColor: model.color) },
                set: { model.color = NSColor($0) }))
            .labelsHidden()
            .help(L("Другой цвет"))

            Menu {
                ForEach([2, 4, 6, 8, 12, 16], id: \.self) { width in
                    Button("\(width)") { model.lineWidth = CGFloat(width) }
                }
            } label: {
                Label("\(Int(model.lineWidth))", systemImage: "lineweight")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("Толщина линий и размер текста"))
        }
    }
}

struct ViewHost: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ToolPicker: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases) { tool in
                let selected = model.tool == tool
                Button {
                    model.tool = tool
                    if tool == .emoji { model.showEmojiPicker = true }
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 26)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selected ? Color.accentColor : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tool.title)
                .popover(isPresented: tool == .emoji ? $model.showEmojiPicker : .constant(false), arrowEdge: .bottom) {
                    EmojiPickerView(model: model)
                }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.7)))
    }
}

struct StylePicker: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Array(EditorModel.palette.enumerated()), id: \.offset) { _, color in
                    let selected = model.color.isClose(to: color)
                    Button {
                        model.color = color
                    } label: {
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                            .padding(2)
                            .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: model.color) },
                    set: { model.color = NSColor($0) }))
                .labelsHidden()
                .help(L("Другой цвет"))
            }
            Divider().frame(height: 20)
            HStack(spacing: 6) {
                Image(systemName: "lineweight").foregroundStyle(.secondary)
                Slider(value: $model.lineWidth, in: 2...16, step: 1)
                    .frame(width: 90)
                    .controlSize(.small)
                Text("\(Int(model.lineWidth))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            .help(L("Толщина линий и размер текста"))
        }
    }
}

struct HistoryButtons: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 4) {
            Button { model.canvas?.undo(nil) } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo).help(L("Отменить (⌘Z)"))
            Button { model.canvas?.redo(nil) } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo).help(L("Повторить (⇧⌘Z)"))
        }
        .buttonStyle(.borderless)
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 4)
    }
}

struct ShareButtons: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var servers = ServerSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            if servers.servers.filter(\.isConfigured).count > 1 {
                ServerPicker(label: servers.active?.displayName)
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.system(size: 12))
            }
            Button { model.controller?.copyImage(nil) } label: { Image(systemName: "doc.on.doc") }
                .help(L("Скопировать изображение (⌘C)"))
            Button { model.controller?.saveImage(nil) } label: { Image(systemName: "square.and.arrow.down") }
                .disabled(model.isUploading)
                .help(L("Сохранить как… (⌘S)"))
            Button {
                model.controller?.uploadImage(nil)
            } label: {
                HStack(spacing: 6) {
                    if model.isUploading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                    Text(model.isUploading ? L("Загрузка…") : L("Загрузить"))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isUploading)
            .help(L("Загрузить на FTP/SFTP (⌘U)"))
        }
        .controlSize(.large)
    }
}

struct StatusBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 10) {
            Label("\(Int(model.imageSize.width)) × \(Int(model.imageSize.height))", systemImage: "aspectratio")
                .foregroundStyle(.secondary)
            Text(model.tool == .emoji
                 ? L("Выберите эмодзи и кликните по скриншоту — или протяните рамку нужного размера")
                 : L("Shift — ровные линии и квадраты · Двойной клик — редактировать текст · ⌫ — удалить"))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            Button { model.controller?.setZoom(model.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int((model.zoom * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44)
            Button { model.controller?.setZoom(model.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
            Button(L("Вписать")) { model.controller?.zoomToFit() }
            Button("100%") { model.controller?.setZoom(1) }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(.bar)
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(toast.isError ? Color.red : Color.green)
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 560)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

extension NSImage {
    static func swatch(_ color: NSColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.setFill()
            circle.fill()
            NSColor.gray.withAlphaComponent(0.5).setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            return true
        }
    }
}

extension NSColor {
    func isClose(to other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01
            && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}
