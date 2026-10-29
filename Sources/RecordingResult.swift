import AppKit
import AVKit
import SwiftUI

final class RecordingResultModel: ObservableObject {
    let fileURL: URL
    let player: AVPlayer
    @Published var duration: TimeInterval = 0
    @Published var videoSize: CGSize = .zero
    @Published var isUploading = false {
        didSet { controller?.window?.standardWindowButton(.closeButton)?.isEnabled = !isUploading }
    }
    @Published var savedURL: URL?
    @Published var uploaded = false
    @Published var toast: Toast?
    weak var controller: RecordingResultWindowController?

    var fileName: String { fileURL.lastPathComponent }
    var fileSize: Int64 { Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

    init(fileURL: URL) {
        self.fileURL = fileURL
        player = AVPlayer(url: fileURL)
    }

    func load() async {
        let asset = AVURLAsset(url: fileURL)
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        var size = CGSize.zero
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize) {
            size = natural
        }
        let videoSize = size
        await MainActor.run {
            self.duration = duration
            self.videoSize = videoSize
        }
    }

    func showToast(_ toast: Toast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + (toast.isError ? 6 : 4)) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

final class RecordingResultWindowController: NSWindowController, NSWindowDelegate {
    private let model: RecordingResultModel
    var onClose: ((RecordingResultWindowController) -> Void)?

    init(fileURL: URL) {
        model = RecordingResultModel(fileURL: fileURL)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("Запись — ") + fileURL.lastPathComponent
        window.minSize = NSSize(width: 420, height: 340)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        model.controller = self
        window.delegate = self
        let hosting = NSHostingView(rootView: Localized { RecordingResultView(model: self.model) })
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        WindowButtons.keepColored(window)

        Task { @MainActor in
            await model.load()
            fitWindowToVideo()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Sizes the window to the video's aspect ratio, within 70% of the screen.
    private func fitWindowToVideo() {
        guard let window, model.videoSize.width > 0, model.videoSize.height > 0 else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let controlsHeight: CGFloat = 144
        let maxW = visible.width * 0.7, maxH = visible.height * 0.7 - controlsHeight
        let scale = min(maxW / model.videoSize.width, maxH / model.videoSize.height, 1)
        let width = max(model.videoSize.width * scale, 520)
        let height = model.videoSize.height * scale + controlsHeight
        window.setContentSize(NSSize(width: width, height: max(height, 340)))
        window.center()
    }

    // MARK: Actions

    func save() {
        guard !model.isUploading else { return }
        let folder = RecordingSettings.shared.folderURL
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = Self.uniqueURL(folder.appendingPathComponent(model.fileName))
            try FileManager.default.copyItem(at: model.fileURL, to: target)
            model.savedURL = target
            NSWorkspace.shared.activateFileViewerSelecting([target])
            HUD.saved(target)
            discard()
        } catch {
            model.showToast(Toast(message: error.localizedDescription, isError: true))
        }
    }

    func saveAs() {
        guard !model.isUploading, let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = model.fileName
        panel.directoryURL = RecordingSettings.shared.folderURL
        panel.isExtensionHidden = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try FileManager.default.copyItem(at: self.model.fileURL, to: url)
                self.model.savedURL = url
                HUD.saved(url)
                self.discard()
            } catch {
                self.model.showToast(Toast(message: error.localizedDescription, isError: true))
            }
        }
    }

    func upload() {
        guard !model.isUploading else { return }
        let settings = ServerSettings.shared
        guard let config = settings.activeConfig else {
            AppDelegate.shared?.showSettings(tab: .server)
            return
        }
        let fileURL = model.fileURL
        // Same as the editor: hidden during the upload, closed on success, shown again otherwise.
        let job = UploadJob(
            fileName: model.fileName, serverName: settings.active?.displayName ?? config.host,
            send: { progress in try await Uploader.upload(file: fileURL, config: try currentServerConfig(), progress: progress) },
            onUpdate: { [weak self] state in
                guard let self else { return }
                self.model.isUploading = state == .uploading
                switch state {
                case .uploading:
                    self.model.player.pause()
                    self.window?.orderOut(nil)
                case .succeeded:
                    self.model.uploaded = true
                    self.discard()
                case .failed, .cancelled:
                    self.window?.makeKeyAndOrderFront(nil)
                }
            })
        job.start()
    }

    func discard() {
        guard !model.isUploading else { return }
        close()
    }

    // MARK: Window

    /// Closing mid-upload is blocked: closing deletes the temporary file the upload is still reading.
    func windowShouldClose(_ sender: NSWindow) -> Bool { !model.isUploading }

    func windowWillClose(_ notification: Notification) {
        model.player.pause()
        try? FileManager.default.removeItem(at: model.fileURL.deletingLastPathComponent())
        onClose?(self)
    }

    private static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var n = 2
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

struct RecordingResultView: View {
    @ObservedObject var model: RecordingResultModel
    @ObservedObject private var servers = ServerSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            PlayerView(player: model.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(info).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    if let saved = model.savedURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([saved])
                        } label: {
                            Label(L("Сохранено: %@", (saved.path as NSString).abbreviatingWithTildeInPath), systemImage: "checkmark.circle.fill")
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .buttonStyle(.hand(.link))
                        .help(L("Показать в Finder"))
                    } else if model.uploaded {
                        Label(L("Загружено на сервер"), systemImage: "checkmark.icloud.fill").foregroundStyle(.green)
                    }
                }
                .font(.system(size: 11))

                ViewThatFits(in: .horizontal) {
                    buttons(compact: false)
                    buttons(compact: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 12)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
    }

    private var info: String {
        var parts = [RecordingControlsView.format(model.duration)]
        parts.append(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
        if model.videoSize.width > 0 { parts.append("\(Int(model.videoSize.width)) × \(Int(model.videoSize.height))") }
        return parts.joined(separator: " · ")
    }

    private func buttons(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                model.controller?.discard()
            } label: {
                Label(L("Удалить"), systemImage: "trash").labelStyle(style(compact))
            }
            .disabled(model.isUploading)
            .help(L("Удалить запись и закрыть окно"))
            Spacer(minLength: 8)
            if servers.servers.filter(\.isConfigured).count > 1 {
                ServerPicker(label: compact ? nil : servers.active?.displayName)
                    .fixedSize()
            }
            Button {
                model.controller?.upload()
            } label: {
                HStack(spacing: 6) {
                    if model.isUploading { ProgressView().controlSize(.small) }
                    Label(model.isUploading ? L("Загрузка…") : L("Загрузить на сервер"), systemImage: "icloud.and.arrow.up")
                        .labelStyle(style(compact && !model.isUploading))
                }
            }
            .disabled(model.isUploading)
            .help(servers.isConfigured ? L("Загрузить на «%@»", servers.active?.displayName ?? "") : L("Сначала настройте сервер"))
            Button {
                model.controller?.saveAs()
            } label: {
                Label(L("Сохранить как…"), systemImage: "square.and.arrow.down.on.square").labelStyle(style(compact))
            }
            .disabled(model.isUploading)
            .help(L("Выбрать, куда сохранить видео"))
            Button {
                model.controller?.save()
            } label: {
                Label(L("Сохранить"), systemImage: "square.and.arrow.down").labelStyle(style(compact))
            }
            .buttonStyle(.hand(.borderedProminent))
            .keyboardShortcut(.defaultAction)
            .disabled(model.isUploading)
            .help(L("Сохранить в %@", RecordingSettings.shared.folderDisplay))
        }
        .controlSize(.large)
    }

    private func style(_ compact: Bool) -> AnyLabelStyle {
        compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon)
    }
}

private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
