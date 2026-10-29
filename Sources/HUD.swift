import AppKit
import SwiftUI

/// Floating notifications shown over all apps: upload progress, results, errors and short messages.
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?
    private static var hideDelay: TimeInterval?
    private static var hovering = false
    /// Bumped on every new notification so a stale upload can't overwrite a newer message.
    private static var generation = 0

    /// Compact capsule with an icon and a line of text.
    static func show(_ message: String, detail: String? = nil, isError: Bool = false) {
        present(PillNotice(title: message, detail: detail, isError: isError),
                hideAfter: isError ? 5 : 2.5)
    }

    /// "Saved" card with a file-type icon and a button that reveals the file.
    static func saved(_ url: URL) {
        present(SavedCard(url: url), hideAfter: 5)
    }

    /// Shows the job's card and keeps it in sync until the job ends.
    static func show(_ job: UploadJob) {
        let id = present(UploadCard(job: job), hideAfter: nil)
        job.onStateChange = { [weak job] state in
            guard let job, generation == id else { return }
            switch state {
            case .uploading: break
            case .succeeded: present(UploadCard(job: job), hideAfter: 4)
            case .failed: present(UploadCard(job: job), hideAfter: 7)
            case .cancelled: hide()
            }
        }
    }

    static func hide() {
        hideWork?.cancel()
        hideDelay = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                             completionHandler: { if panel.alphaValue == 0 { panel.orderOut(nil) } })
    }

    @discardableResult
    private static func present<Content: View>(_ content: Content, hideAfter delay: TimeInterval?) -> Int {
        generation += 1
        let root = Localized {
            content
                .onHover { HUD.setHovering($0) }
                .padding(24)
        }
        let hosting = FirstClickHostingView(rootView: root)
        let size = hosting.fittingSize

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let wasVisible = panel.isVisible && panel.alphaValue > 0
        panel.contentView = hosting

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height + 6,
                           width: size.width, height: size.height)
        if wasVisible {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
        } else {
            panel.setFrame(frame.offsetBy(dx: 0, dy: 10), display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        }
        panel.orderFrontRegardless()

        hideDelay = delay
        scheduleHide()
        return generation
    }

    private static func setHovering(_ value: Bool) {
        hovering = value
        scheduleHide()
    }

    /// Hiding waits while the pointer is over the notification, so its buttons stay reachable.
    private static func scheduleHide() {
        hideWork?.cancel()
        guard let delay = hideDelay, !hovering else { return }
        let work = DispatchWorkItem { hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

/// The notification panel never becomes active, so its buttons must react to the very first click.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Upload job

/// One upload, from start to its result, with progress, cancel and retry for the notification card.
@MainActor
final class UploadJob: ObservableObject {
    enum State: Equatable {
        case uploading
        case succeeded(link: String?, remoteName: String, linkCopied: Bool)
        case failed(String)
        case cancelled
    }

    /// Name shown while uploading, e.g. `shotty_2026-10-29_14-09-39.png`.
    let fileName: String
    /// Server of the current attempt; Retry may go to a different one if the user switched.
    @Published private(set) var serverName: String
    @Published var state: State = .uploading
    /// Nil until the file starts going out (connecting, checking names on the server).
    @Published var progress: Double?
    var onStateChange: ((State) -> Void)?
    /// The owner's reaction: hide its window on `.uploading`, close it on success, bring it back otherwise.
    private let onUpdate: (State) -> Void
    private let send: (@escaping @Sendable (Double) -> Void) async throws -> UploadResult
    private var task: Task<Void, Never>?

    init(fileName: String, serverName: String,
         send: @escaping (@escaping @Sendable (Double) -> Void) async throws -> UploadResult,
         onUpdate: @escaping (State) -> Void) {
        self.fileName = fileName
        self.serverName = serverName
        self.send = send
        self.onUpdate = onUpdate
    }

    var isRunning: Bool { state == .uploading }

    /// Each attempt, Retry included, uploads with the server settings as they are right now.
    func start() {
        task?.cancel()
        progress = nil
        if let name = ServerSettings.shared.active?.displayName { serverName = name }
        setState(.uploading)
        HUD.show(self)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await send { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.isRunning, fraction > (self.progress ?? 0) else { return }
                        self.progress = fraction
                    }
                }
                guard !Task.isCancelled else { return setState(.cancelled) }
                progress = 1
                var copied = false
                if let link = result.link, ServerSettings.shared.copyLinkAfterUpload {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                    copied = true
                }
                setState(.succeeded(link: result.link, remoteName: result.fileName, linkCopied: copied))
            } catch {
                if Task.isCancelled || error is CancellationError { return setState(.cancelled) }
                setState(.failed(error.localizedDescription))
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        task?.cancel()
    }

    private func setState(_ state: State) {
        self.state = state
        onUpdate(state)
        onStateChange?(state)
    }
}

// MARK: - Views

struct UploadCard: View {
    @ObservedObject var job: UploadJob
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch job.state {
        case .uploading, .cancelled: uploading
        case let .succeeded(link, remoteName, copied): succeeded(link: link, remoteName: remoteName, copied: copied)
        case let .failed(message): FailedCard(job: job, message: message)
        }
    }

    private var uploading: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                NoticeIcon(symbol: "arrow.up", tint: scheme == .dark ? Glass.hex(0x8FB0FF) : Glass.hex(0x1F4FA6),
                           background: scheme == .dark ? Color.white.opacity(0.08) : Glass.hex(0x1F4FA6, 0.12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Загрузка на %@…", job.serverName))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(job.fileName + (job.progress.map { " · \(Int($0 * 100))%" } ?? ""))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Glass.secondaryText(scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                NoticeButton(title: L("Отмена")) { job.cancel() }
            }
            ProgressTrack(progress: job.progress)
        }
        .noticeCard(scheme, padding: EdgeInsets(top: 10, leading: 14, bottom: 13, trailing: 14))
    }

    private func succeeded(link: String?, remoteName: String, copied: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Glass.hex(0x22C55E))
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Glass.hex(0x0B1A12) : .white)
            }
            .frame(width: 33, height: 33)
            .shadow(color: Glass.hex(0x22C55E, 0.55), radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(copied ? L("Ссылка скопирована") : L("Загружено на «%@»", job.serverName))
                    .font(.system(size: 13, weight: .semibold))
                Text(link.map(Self.withoutScheme) ?? remoteName)
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.secondaryText(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .noticeCard(scheme, padding: EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 16))
    }

    private static func withoutScheme(_ link: String) -> String {
        for prefix in ["https://", "http://"] where link.hasPrefix(prefix) { return String(link.dropFirst(prefix.count)) }
        return link
    }
}

/// Red error card: shakes once when it appears, offers Retry and a close button.
private struct FailedCard: View {
    let job: UploadJob
    let message: String
    @State private var shake: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let red = scheme == .dark ? Glass.hex(0xFF5A64) : Glass.hex(0xD9001B)
        HStack(spacing: 12) {
            NoticeIcon(symbol: "exclamationmark.circle", tint: red,
                       background: red.opacity(scheme == .dark ? 0.16 : 0.12))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Не удалось загрузить"))
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(scheme == .dark ? Glass.hex(0xF3C6CC, 0.85) : Glass.hex(0x6E1E2B, 0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(message)
            }
            Spacer(minLength: 8)
            Button { job.start() } label: {
                Text(AppPreferences.shared.language == .en ? "Retry" : "Повторить")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(scheme == .dark ? Glass.hex(0x2A0A10) : .white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(red))
                    .contentShape(Capsule())
            }
            .buttonStyle(.hand(.plain))
            Button { HUD.hide() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Glass.hex(0xF3C6CC, 0.85) : Glass.hex(0x6E1E2B, 0.8))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(red.opacity(scheme == .dark ? 0.16 : 0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.hand(.plain))
            .help(L("Закрыть"))
        }
        .noticeCard(scheme, padding: EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 12), tint: red)
        .modifier(ShakeEffect(progress: shake))
        .onAppear {
            withAnimation(.linear(duration: 0.5)) { shake = 1 }
        }
    }
}

/// Side-to-side "no" shake that fades out as `progress` goes from 0 to 1.
private struct ShakeEffect: GeometryEffect {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(progress * .pi * 8) * 8 * (1 - progress)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

struct SavedCard: View {
    let url: URL
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            SavedFileIcon(isVideo: ["mp4", "mov"].contains(url.pathExtension.lowercased()))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Glass.hex(0x22B04B))
                    Text(L("Сохранено"))
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(url.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.secondaryText(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            NoticeButton(title: L("Показать в Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                HUD.hide()
            }
        }
        .noticeCard(scheme, padding: EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 14))
    }
}

/// Tinted tile with a framed photo or play glyph: blue for images, violet for videos.
struct SavedFileIcon: View {
    let isVideo: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let tile = isVideo ? (dark ? 0x392E55 : 0xF0EAFB) : (dark ? 0x233957 : 0xE2ECFB)
        let line = isVideo ? (dark ? 0xC0ABFE : 0x8963DE) : (dark ? 0x87BAFC : 0x4185E3)
        let inner = isVideo ? (dark ? 0x4E4372 : 0xE3DBF8) : (dark ? 0x344E72 : 0xD0E0F9)
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Glass.hex(UInt32(tile)))
            .frame(width: 53, height: 43)
            .overlay {
                Canvas { context, size in
                    // Drawn on a 24-unit grid with a 1.75 pt line.
                    context.scaleBy(x: size.width / 24, y: size.height / 24)
                    let frame = Path(roundedRect: CGRect(x: 3, y: 4.5, width: 18, height: 15), cornerRadius: 3.2)
                    context.fill(frame, with: .color(Glass.hex(UInt32(inner))))
                    let stroke = StrokeStyle(lineWidth: 1.75 * 24 / size.width, lineCap: .round, lineJoin: .round)
                    let color = GraphicsContext.Shading.color(Glass.hex(UInt32(line)))
                    if isVideo {
                        var play = Path()
                        play.move(to: CGPoint(x: 10, y: 8.6))
                        play.addLine(to: CGPoint(x: 15.6, y: 12))
                        play.addLine(to: CGPoint(x: 10, y: 15.4))
                        play.closeSubpath()
                        context.fill(play, with: color)
                        context.stroke(play, with: color, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                    } else {
                        var hills = Path()
                        hills.move(to: CGPoint(x: 3.6, y: 17.2))
                        hills.addLine(to: CGPoint(x: 9, y: 11.8))
                        hills.addLine(to: CGPoint(x: 16.4, y: 19))
                        hills.move(to: CGPoint(x: 12.4, y: 15))
                        hills.addLine(to: CGPoint(x: 14.6, y: 13))
                        hills.addLine(to: CGPoint(x: 20.4, y: 18.4))
                        context.stroke(hills, with: color, style: stroke)
                        context.stroke(Path(ellipseIn: CGRect(x: 13.8, y: 7.6, width: 3.6, height: 3.6)),
                                       with: color, style: stroke)
                    }
                    context.stroke(frame, with: color, style: stroke)
                }
                .frame(width: 25, height: 25)
            }
    }
}

/// Short message in a capsule, e.g. "Text copied · 128 characters".
struct PillNotice: View {
    let title: String
    var detail: String?
    var isError = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 9) {
            let tint = isError ? (scheme == .dark ? Glass.hex(0xFF5A64) : Glass.hex(0xD9001B))
                               : (scheme == .dark ? Glass.hex(0x6EE0A0) : Glass.hex(0x1E8F55))
            ZStack {
                Circle().fill(tint)
                Image(systemName: isError ? "exclamationmark" : "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Glass.hex(0x0B1A12) : .white)
            }
            .frame(width: 21, height: 21)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: titleWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text("· " + detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Glass.secondaryText(scheme))
                    .fixedSize()
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 21, style: .continuous).fill(noticeTint(scheme)))
        .background(RoundedRectangle(cornerRadius: 21, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).strokeBorder(noticeBorder(scheme)).allowsHitTesting(false))
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.14), radius: 12, y: 4)
        .fixedSize()
    }

    /// One line when it fits, otherwise wrapped at 420 pt so long errors stay readable.
    private var titleWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        return min(ceil((title as NSString).size(withAttributes: [.font: font]).width) + 1, 420)
    }
}

private struct NoticeIcon: View {
    let symbol: String
    let tint: Color
    let background: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 33, height: 33)
            .background(Circle().fill(background))
    }
}

private struct NoticeButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .glassCapsule(scheme, strong: true)
        }
        .buttonStyle(.hand(.plain))
    }
}

/// Thin progress bar; slides back and forth while the amount is unknown.
private struct ProgressTrack: View {
    let progress: Double?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let fill = scheme == .dark ? Glass.hex(0x8FB0FF) : Glass.hex(0x1F4FA6)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(scheme == .dark ? Color.white.opacity(0.1) : Glass.hex(0x1B2433, 0.1))
                if let progress {
                    Capsule().fill(fill)
                        .frame(width: max(4, geo.size.width * progress))
                        .animation(.easeOut(duration: 0.25), value: progress)
                } else {
                    // Runs the whole track: enters at the left edge and leaves past the right one.
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        let width = geo.size.width * 0.28
                        Capsule().fill(fill)
                            .frame(width: width)
                            .offset(x: (geo.size.width + width) * t - width)
                            .frame(width: geo.size.width, alignment: .leading)
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
    }
}

private func noticeTint(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Glass.hex(0x0B1A33, 0.82) : Color.white.opacity(0.55)
}

private func noticeBorder(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.9)
}

private extension View {
    /// Rounded glass card, 450 pt wide; `tint` turns it into an error card.
    func noticeCard(_ scheme: ColorScheme, padding: EdgeInsets, tint: Color? = nil) -> some View {
        self
            .padding(padding)
            .frame(width: 450)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(noticeTint(scheme)))
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.regularMaterial))
            // Decoration only: overlays sit above the buttons and would swallow their clicks.
            .overlay {
                if let tint {
                    RoundedRectangle(cornerRadius: 26, style: .continuous).fill(tint.opacity(scheme == .dark ? 0.1 : 0.08))
                        .allowsHitTesting(false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(tint.map { $0.opacity(scheme == .dark ? 0.35 : 0.3) } ?? noticeBorder(scheme))
                .allowsHitTesting(false))
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.14), radius: 14, y: 5)
    }
}
