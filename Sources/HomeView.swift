import AppKit
import SwiftUI

struct HomeView: View {
    let onAction: (HotKeyAction) -> Void
    let onSettings: (SettingsTab) -> Void
    @ObservedObject private var settings = ServerSettings.shared
    @ObservedObject private var hotKeys = HotKeySettings.shared
    @ObservedObject private var preferences = AppPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shotty")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(L("Снимки экрана, стрелки, рамки, текст и загрузка на сервер"))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 14)

            HStack(spacing: 12) {
                CaptureCard(symbol: "rectangle.dashed", title: L("Область"), shortcut: shortcut(.area),
                            colors: [.blue, .cyan]) { onAction(.area) }
                CaptureCard(symbol: "macwindow", title: L("Окно"), shortcut: shortcut(.window),
                            colors: [.purple, .pink]) { onAction(.window) }
                CaptureCard(symbol: "display", title: L("Весь экран"), shortcut: shortcut(.fullScreen),
                            colors: [.orange, .red]) { onAction(.fullScreen) }
            }

            HStack(spacing: 12) {
                CaptureCard(symbol: "text.viewfinder", title: L("Текст из области"), shortcut: shortcut(.ocr),
                            colors: [.teal, .green]) { onAction(.ocr) }
                CaptureCard(symbol: "record.circle", title: L("Запись видео"), shortcut: shortcut(.record),
                            colors: [.red, .pink]) { onAction(.record) }
            }

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(settings.isConfigured ? Color.green.gradient : Color.gray.gradient)
                    Image(systemName: "server.rack")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.isConfigured ? (settings.active?.displayName ?? "") : L("Сервер не настроен"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(settings.isConfigured
                         ? (settings.active?.summary ?? "")
                         : L("Укажите FTP или SFTP, чтобы загружать снимки"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if settings.servers.filter(\.isConfigured).count > 1 {
                    ServerPicker()
                        .fixedSize()
                }
                Button(L("Настроить…")) { onSettings(.server) }
                    .controlSize(.large)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))

            HStack {
                Spacer()
                Button {
                    preferences.language = preferences.language == .ru ? .en : .ru
                } label: {
                    Label(preferences.language == .ru ? "RU" : "EN", systemImage: "globe")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.link)
                .help(L("Сменить язык"))
                Button {
                    preferences.toggleDarkMode()
                } label: {
                    Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.link)
                .help(L("Переключить тёмную тему"))
                Button {
                    onSettings(.general)
                } label: {
                    Label(L("Горячие клавиши"), systemImage: "keyboard")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: 600)
    }
}

extension HomeView {
    private func shortcut(_ action: HotKeyAction) -> String {
        hotKeys.hotKey(for: action)?.displayString ?? L("без сочетания")
    }
}

/// Menu for choosing which configured server uploads go to.
struct ServerPicker: View {
    @ObservedObject private var settings = ServerSettings.shared
    var label: String? = nil

    var body: some View {
        Menu {
            ForEach(settings.servers.filter(\.isConfigured)) { server in
                Toggle(isOn: Binding(get: { server.id == settings.active?.id },
                                     set: { if $0 { settings.activeID = server.id } })) {
                    Text(server.displayName)
                }
            }
        } label: {
            Label(label ?? L("Сменить"), systemImage: "arrow.triangle.2.circlepath")
        }
        .help(L("Выбрать сервер для загрузки"))
    }
}

struct CaptureCard: View {
    let symbol: String
    let title: String
    let shortcut: String
    let colors: [Color]
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: colors[0].opacity(0.4), radius: hovering ? 10 : 5, y: 3)
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.quaternary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.background.opacity(hovering ? 0.9 : 0.55)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovering ? 0.14 : 0.07)))
            .scaleEffect(hovering ? 1.02 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
    }
}
