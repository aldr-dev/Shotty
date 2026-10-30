import AppKit
import SwiftUI

/// Colors of the "Glass" design shared by the home window and the floating notifications.
enum Glass {
    static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(.sRGB, red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: opacity)
    }

    static func background(_ scheme: ColorScheme) -> LinearGradient {
        let stops: [Gradient.Stop] = scheme == .dark
            ? [.init(color: hex(0x0B3D7C), location: 0), .init(color: hex(0x04193A), location: 0.42),
               .init(color: hex(0x031632), location: 0.62), .init(color: hex(0x0A3A72), location: 1)]
            : [.init(color: hex(0x8EAED8), location: 0), .init(color: hex(0xD5E3F4), location: 0.42),
               .init(color: hex(0xCADBF2), location: 0.64), .init(color: hex(0x8FAFDD), location: 1)]
        return LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Translucent fill of cards and pills.
    static func fill(_ scheme: ColorScheme, hovering: Bool = false) -> Color {
        scheme == .dark ? .white.opacity(hovering ? 0.11 : 0.065) : .white.opacity(hovering ? 0.78 : 0.55)
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.11) : .white.opacity(0.85)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.62) : hex(0x3C4452, 0.85)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0x8DB8FF) : hex(0x1E5FC4)
    }

    static func chip(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.1) : hex(0x1B2433, 0.08)
    }

    static let shadow = Color(.sRGB, red: 0.1, green: 0.2, blue: 0.4, opacity: 0.12)
}

struct HomeView: View {
    let onAction: (HotKeyAction) -> Void
    let onSettings: (SettingsTab) -> Void
    @ObservedObject private var settings = ServerSettings.shared
    @ObservedObject private var hotKeys = HotKeySettings.shared
    @ObservedObject private var preferences = AppPreferences.shared
    @Environment(\.colorScheme) private var scheme
    @State private var showServers = false

    static let width: CGFloat = 600
    static let height: CGFloat = 525

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 62, height: 62)
                    // App icons carry a transparent margin; this keeps the visible tile at 52 pt.
                    .padding(-5)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shotty")
                        .font(.system(size: 22, weight: .bold))
                    Text(L("Снимки, разметка и загрузка на свой сервер"))
                        .font(.system(size: 12))
                        .foregroundStyle(Glass.secondaryText(scheme))
                }
            }

            HStack(spacing: 11) {
                CaptureCard(symbol: "rectangle.dashed", title: L("Область"), hotKey: hotKey(.area),
                            tint: scheme == .dark ? Glass.hex(0x8FB0FF) : Glass.hex(0x2F6BE0),
                            onSetShortcut: { onSettings(.general) }) { onAction(.area) }
                CaptureCard(symbol: "macwindow", title: L("Окно"), hotKey: hotKey(.window),
                            tint: scheme == .dark ? Glass.hex(0xC6A6FF) : Glass.hex(0x8A43E6),
                            onSetShortcut: { onSettings(.general) }) { onAction(.window) }
                CaptureCard(symbol: "display", title: L("Весь экран"), hotKey: hotKey(.fullScreen),
                            tint: scheme == .dark ? Glass.hex(0xFFA764) : Glass.hex(0xE36D1C),
                            onSetShortcut: { onSettings(.general) }) { onAction(.fullScreen) }
            }
            .padding(.top, 18)

            HStack(spacing: 11) {
                ActionPill(symbol: "text.viewfinder", title: L("Текст из области"), hotKey: hotKey(.ocr),
                           tint: scheme == .dark ? Glass.hex(0x7FE3B7) : Glass.hex(0x2E8F6E)) { onAction(.ocr) }
                ActionPill(symbol: "record.circle", title: L("Запись видео"), hotKey: hotKey(.record),
                           tint: scheme == .dark ? Glass.hex(0xFD7477) : Glass.hex(0xE3201C), isRecord: true) { onAction(.record) }
            }
            .padding(.top, 19)

            Spacer(minLength: 16)

            ServerBar(showServers: $showServers, onSettings: { onSettings(.server) })

            Button { onSettings(.general) } label: {
                Text(L("Горячие клавиши…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Glass.accent(scheme))
            }
            .buttonStyle(.hand(.plain))
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
        }
        .padding(.horizontal, 27)
        .padding(.top, 65)
        .padding(.bottom, 18)
        .frame(width: Self.width, height: Self.height)
        .background(Glass.background(scheme))
        .overlayPreferenceValue(ServerMenuAnchor.self) { anchor in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if showServers, let anchor {
                        let button = geo[anchor]
                        // Clicking anywhere else closes the list.
                        Color.black.opacity(0.001)
                            .onTapGesture { showServers = false }
                        ServerList { showServers = false }
                            .fixedSize()
                            .alignmentGuide(.leading) { $0[.trailing] - button.maxX }
                            .alignmentGuide(.top) { $0[.bottom] - button.minY + 8 }
                            .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .animation(.spring(duration: 0.22), value: showServers)
        }
        // The content runs under the transparent title bar; its layout already leaves room for it.
        .ignoresSafeArea()
    }

    private func hotKey(_ action: HotKeyAction) -> String? {
        hotKeys.hotKey(for: action)?.displayString
    }
}

/// Language and theme switches in the top-right corner, on the traffic lights' line.
struct HomeTitleButtons: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 7) {
            Button {
                preferences.language = preferences.language == .ru ? .en : .ru
            } label: {
                Text(preferences.language == .ru ? "RU" : "EN")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 40, height: 27)
                    .glassCapsule(scheme)
            }
            .buttonStyle(.hand(.plain))
            .help(L("Сменить язык"))

            Button {
                preferences.toggleDarkMode()
            } label: {
                Image(systemName: scheme == .dark ? "sun.max" : "moon")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 27, height: 27)
                    .glassCapsule(scheme)
            }
            .buttonStyle(.hand(.plain))
            .help(L("Переключить тёмную тему"))
        }
    }
}

/// Reports whether the hosting window is visible: on screen, not minimized and not fully covered.
private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView(onChange: onChange) }
    func updateNSView(_ view: ReaderView, context: Context) { view.onChange = onChange }

    final class ReaderView: NSView {
        var onChange: (Bool) -> Void
        private var observer: NSObjectProtocol?
        private var visible: Bool?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return report(false) }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportWindowState() }
            }
            reportWindowState()
        }

        private func reportWindowState() {
            report(window?.occlusionState.contains(.visible) ?? false)
        }

        private func report(_ value: Bool) {
            guard value != visible else { return }
            visible = value
            // Called during view updates; changing SwiftUI state there is not allowed.
            DispatchQueue.main.async { [onChange] in onChange(value) }
        }
    }
}

/// Live server: a ring keeps spreading out from the dot.
private struct PulseRing: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Glass.hex(0x22C55E))
            .scaleEffect(pulse ? 2.2 : 0.8)
            .opacity(pulse ? 0 : 0.45)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

private struct ServerBar: View {
    @Binding var showServers: Bool
    let onSettings: () -> Void
    @ObservedObject private var settings = ServerSettings.shared
    @Environment(\.colorScheme) private var scheme
    @State private var windowVisible = false

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(settings.isConfigured ? Glass.hex(0x22C55E) : Color.gray)
                .frame(width: 8, height: 8)
                .padding(3.5)
                .background(Circle().fill((settings.isConfigured ? Glass.hex(0x22C55E) : Color.gray).opacity(0.22)))
                .background {
                    // Only while the window is on screen: the window stays alive when closed, and a
                    // running animation would keep redrawing it every frame.
                    if settings.isConfigured && windowVisible {
                        PulseRing()
                    }
                }
                .shadow(color: settings.isConfigured ? Glass.hex(0x22C55E, 0.6) : .clear, radius: 3)
                .background(WindowVisibilityReader { windowVisible = $0 })

            VStack(alignment: .leading, spacing: 1) {
                Text(settings.isConfigured ? (settings.active?.displayName ?? "") : L("Сервер не настроен"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(settings.isConfigured
                     ? (settings.active?.summary ?? "")
                     : L("Укажите FTP или SFTP, чтобы загружать снимки"))
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.secondaryText(scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)

            if settings.servers.filter(\.isConfigured).count > 1 {
                Button { showServers.toggle() } label: {
                    HStack(spacing: 5) {
                        Text(L("Сменить"))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(showServers ? 180 : 0))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 33)
                    .glassCapsule(scheme, strong: true)
                }
                .buttonStyle(.hand(.plain))
                .anchorPreference(key: ServerMenuAnchor.self, value: .bounds) { $0 }
                .help(L("Выбрать сервер для загрузки"))
            }

            if settings.isConfigured {
                Button(action: onSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 33, height: 33)
                        .glassCapsule(scheme, strong: true)
                }
                .buttonStyle(.hand(.plain))
                .help(L("Настройки сервера"))
            } else {
                Button(action: onSettings) {
                    Text(L("Настроить…"))
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 33)
                        .glassCapsule(scheme, strong: true)
                }
                .buttonStyle(.hand(.plain))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 53)
        .background(Capsule().fill(Glass.fill(scheme)))
        .overlay(Capsule().strokeBorder(Glass.border(scheme)).allowsHitTesting(false))
        .shadow(color: Glass.shadow, radius: 8, y: 3)
    }
}

private struct ServerMenuAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Glass drop-up list of configured servers, opened by "Change" in the server bar.
private struct ServerList: View {
    let onDone: () -> Void
    @ObservedObject private var settings = ServerSettings.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 2) {
            ForEach(settings.servers.filter(\.isConfigured)) { server in
                ServerListRow(server: server, isActive: server.id == settings.active?.id) {
                    settings.activeID = server.id
                    // Let the checkmark move before the list fades out.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: onDone)
                }
            }
        }
        .padding(6)
        .frame(width: 270)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Glass.fill(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Glass.border(scheme)).allowsHitTesting(false))
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.14), radius: 14, y: 6)
    }
}

private struct ServerListRow: View {
    let server: ServerProfile
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Glass.accent(scheme))
                    .opacity(isActive ? 1 : 0)
                    // Jump, don't cross-fade: otherwise both rows show a checkmark for a moment.
                    .transaction { $0.animation = nil }
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(server.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(server.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Glass.secondaryText(scheme))
                        .truncationMode(.middle)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? Glass.chip(scheme) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.hand(.plain))
        .onHover { hovering = $0 }
    }
}

/// Menu for choosing which configured server uploads go to. A plain button that pops up the
/// menu itself: SwiftUI's `Menu` is an AppKit pop-up button that resets the cursor to the arrow.
struct ServerPicker: View {
    @ObservedObject private var settings = ServerSettings.shared
    var label: String? = nil

    var body: some View {
        Button(action: popUp) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                if let label { Text(label) }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.hand(.borderless))
        .help(L("Выбрать сервер для загрузки"))
    }

    private func popUp() {
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let menu = NSMenu()
        var activeItem: NSMenuItem?
        for server in settings.servers where server.isConfigured {
            let item = ServerMenuItem(server: server)
            item.state = server.id == settings.active?.id ? .on : .off
            if item.state == .on { activeItem = item }
            menu.addItem(item)
        }
        menu.popUp(positioning: activeItem, at: view.convert(event.locationInWindow, from: nil), in: view)
    }
}

private final class ServerMenuItem: NSMenuItem {
    private let serverID: UUID

    init(server: ServerProfile) {
        serverID = server.id
        super.init(title: server.displayName, action: #selector(choose), keyEquivalent: "")
        target = self
        toolTip = server.summary
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func choose() {
        ServerSettings.shared.activeID = serverID
    }
}

struct CaptureCard: View {
    let symbol: String
    let title: String
    let hotKey: String?
    let tint: Color
    let onSetShortcut: () -> Void
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(height: 28)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 12)
                Group {
                    if let hotKey {
                        Text(hotKey)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Glass.secondaryText(scheme))
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Glass.chip(scheme)))
                    } else {
                        Button(action: onSetShortcut) {
                            Text(L("+ сочетание"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Glass.secondaryText(scheme))
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Glass.secondaryText(scheme).opacity(0.5),
                                                  style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.hand(.plain))
                        .help(L("Назначить сочетание клавиш"))
                    }
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 124)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Glass.fill(scheme, hovering: hovering)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Glass.border(scheme)).allowsHitTesting(false))
            .shadow(color: Glass.shadow, radius: hovering ? 10 : 6, y: 3)
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.hand(.plain))
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
    }
}

/// Wide capsule button of the second row: OCR and video recording.
struct ActionPill: View {
    let symbol: String
    let title: String
    let hotKey: String?
    let tint: Color
    var isRecord = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: isRecord ? 21 : 18, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if let hotKey {
                    Text(hotKey)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isRecord ? (scheme == .dark ? Glass.hex(0xFFC9CC) : Glass.hex(0x9B1424))
                                                  : Glass.secondaryText(scheme))
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecord ? (scheme == .dark ? Color.white.opacity(0.1) : Glass.hex(0xE3201C, 0.12))
                                           : Glass.chip(scheme)))
                } else {
                    Text("—").foregroundStyle(Glass.secondaryText(scheme))
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 19)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(border).allowsHitTesting(false))
            .shadow(color: Glass.shadow, radius: hovering ? 10 : 6, y: 3)
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.hand(.plain))
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
    }

    private var fill: Color {
        guard isRecord else { return Glass.fill(scheme, hovering: hovering) }
        return scheme == .dark ? Glass.hex(0x3A2140, hovering ? 0.75 : 0.6) : Glass.hex(0xF6E4EC, hovering ? 0.9 : 0.72)
    }

    private var border: Color {
        guard isRecord else { return Glass.border(scheme) }
        return scheme == .dark ? Glass.hex(0xFF5A6A, 0.4) : .white.opacity(0.85)
    }
}

extension View {
    /// Small round glass control: language/theme switches, server buttons.
    func glassCapsule(_ scheme: ColorScheme, strong: Bool = false) -> some View {
        background(Capsule().fill(scheme == .dark ? Color.white.opacity(strong ? 0.1 : 0.08)
                                                  : Color.white.opacity(strong ? 0.85 : 0.6)))
            .overlay(Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.9))
                .allowsHitTesting(false))
            .contentShape(Capsule())
    }
}

/// Toolbar of the home window: only the language and theme switches, at the trailing edge.
final class HomeToolbar: NSObject, NSToolbarDelegate {
    private static let buttons = NSToolbarItem.Identifier("homeButtons")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, Self.buttons] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, Self.buttons] }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.buttons else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        let hosting = NSHostingView(rootView: Localized { HomeTitleButtons() })
        hosting.frame.size = hosting.fittingSize
        item.view = hosting
        item.isBordered = false
        return item
    }
}
