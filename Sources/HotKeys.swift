import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }

    var menuModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }
}

enum HotKeyAction: String, CaseIterable, Identifiable {
    case area, window, fullScreen, ocr, record, switchServer, openHome

    var id: String { rawValue }

    static let captureActions: [HotKeyAction] = [.area, .window, .fullScreen]

    var title: String {
        switch self {
        case .area: L("Снимок области")
        case .window: L("Снимок окна")
        case .fullScreen: L("Снимок всего экрана")
        case .ocr: L("Распознать текст")
        case .record: L("Запись видео (старт/стоп)")
        case .switchServer: L("Сменить сервер загрузки")
        case .openHome: L("Открыть Shotty")
        }
    }

    var symbol: String {
        switch self {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .fullScreen: "display"
        case .ocr: "text.viewfinder"
        case .record: "record.circle"
        case .switchServer: "arrow.triangle.2.circlepath"
        case .openHome: "macwindow.on.rectangle"
        }
    }

    var defaultHotKey: HotKey {
        let mods = UInt32(cmdKey | shiftKey)
        let optMods = UInt32(cmdKey | shiftKey | optionKey)
        switch self {
        case .area: return HotKey(keyCode: UInt32(kVK_ANSI_7), modifiers: mods)
        case .window: return HotKey(keyCode: UInt32(kVK_ANSI_8), modifiers: mods)
        case .fullScreen: return HotKey(keyCode: UInt32(kVK_ANSI_9), modifiers: mods)
        case .ocr: return HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: optMods)
        case .record: return HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: optMods)
        case .switchServer: return HotKey(keyCode: UInt32(kVK_ANSI_U), modifiers: optMods)
        case .openHome: return HotKey(keyCode: UInt32(kVK_ANSI_O), modifiers: optMods)
        }
    }

    var carbonID: UInt32 {
        switch self {
        case .area: 1
        case .window: 2
        case .fullScreen: 3
        case .ocr: 4
        case .record: 5
        case .switchServer: 6
        case .openHome: 7
        }
    }
}

final class HotKeySettings: ObservableObject {
    static let shared = HotKeySettings()

    @Published private(set) var keys: [HotKeyAction: HotKey] = [:]
    @Published var failedActions: Set<HotKeyAction> = []

    /// Called whenever bindings change or recording ends, so the app can re-register.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    private init() {
        for action in HotKeyAction.allCases {
            if let data = defaults.data(forKey: storageKey(action)) {
                if let key = try? JSONDecoder().decode(HotKey?.self, from: data) {
                    keys[action] = key
                }
            } else {
                keys[action] = action.defaultHotKey
            }
        }
    }

    private func storageKey(_ action: HotKeyAction) -> String { "hotkey.\(action.rawValue)" }

    func hotKey(for action: HotKeyAction) -> HotKey? { keys[action] }

    func display(for action: HotKeyAction) -> String { keys[action]?.displayString ?? L("Не задано") }

    func set(_ key: HotKey?, for action: HotKeyAction) {
        keys[action] = key
        if let data = try? JSONEncoder().encode(key) {
            defaults.set(data, forKey: storageKey(action))
        }
        onChange?()
    }

    func resetToDefaults() {
        for action in HotKeyAction.allCases {
            keys[action] = action.defaultHotKey
            defaults.removeObject(forKey: storageKey(action))
        }
        onChange?()
    }

    func action(using key: HotKey, except: HotKeyAction) -> HotKeyAction? {
        HotKeyAction.allCases.first { $0 != except && keys[$0] == key }
    }

    func beginRecording() { HotKeyManager.shared.unregisterAll() }

    func endRecording() { onChange?() }
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false

    @discardableResult
    func register(id: UInt32, hotKey: HotKey, handler: @escaping () -> Void) -> Bool {
        installIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5348_5459), id: id)
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        handlers[id] = handler
        refs.append(ref)
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(_ id: UInt32) { handlers[id]?() }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyManager.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

enum KeyNames {
    private static let names: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
        kVK_Space: "Пробел", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_ANSI_Keypad0: "Num0", kVK_ANSI_Keypad1: "Num1", kVK_ANSI_Keypad2: "Num2", kVK_ANSI_Keypad3: "Num3",
        kVK_ANSI_Keypad4: "Num4", kVK_ANSI_Keypad5: "Num5", kVK_ANSI_Keypad6: "Num6", kVK_ANSI_Keypad7: "Num7",
        kVK_ANSI_Keypad8: "Num8", kVK_ANSI_Keypad9: "Num9", kVK_ANSI_KeypadDecimal: "Num.",
        kVK_ANSI_KeypadMultiply: "Num*", kVK_ANSI_KeypadPlus: "Num+", kVK_ANSI_KeypadDivide: "Num/",
        kVK_ANSI_KeypadMinus: "Num-", kVK_ANSI_KeypadEquals: "Num=", kVK_ANSI_KeypadEnter: "⌤",
    ]

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    static func name(for keyCode: UInt32) -> String { names[Int(keyCode)].map { L($0) } ?? L("Клавиша %ld", Int(keyCode)) }

    static func isKnown(_ keyCode: UInt32) -> Bool { names[Int(keyCode)] != nil }

    static func isFunctionKey(_ keyCode: UInt32) -> Bool { functionKeys.contains(Int(keyCode)) }

    /// Key equivalent string for NSMenuItem (shown next to the item); empty if the key can't be expressed.
    static func menuKeyEquivalent(for keyCode: UInt32) -> String {
        let code = Int(keyCode)
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        if let index = fKeys.firstIndex(of: code), let scalar = UnicodeScalar(NSF1FunctionKey + index) {
            return String(Character(scalar))
        }
        let special: [Int: Int] = [kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
                                   kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey,
                                   kVK_Home: NSHomeFunctionKey, kVK_End: NSEndFunctionKey,
                                   kVK_PageUp: NSPageUpFunctionKey, kVK_PageDown: NSPageDownFunctionKey]
        if let value = special[code], let scalar = UnicodeScalar(value) { return String(Character(scalar)) }
        switch code {
        case kVK_Space: return " "
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        default: break
        }
        guard let name = names[code], name.count == 1 else { return "" }
        return name.lowercased()
    }
}

// MARK: - Settings UI

extension HotKeyAction {
    /// Row title in Settings; the recording hint moves to `settingsDetail`.
    var settingsTitle: String { self == .record ? L("Запись видео") : title }

    var settingsDetail: String? { self == .record ? L("старт/стоп") : nil }

    var settingsSymbol: String {
        switch self {
        case .record: "record"
        case .openHome: "app"
        case .switchServer: "arrow.triangle.2.circlepath"
        default: symbol
        }
    }

    var settingsTint: SettingsStyle.Icon {
        switch self {
        case .area: .blue
        case .window: .purple
        case .fullScreen: .orange
        case .ocr: .green
        case .record: .red
        case .switchServer, .openHome: .teal
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var hotKeys = HotKeySettings.shared
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSection(L("Интерфейс")) {
                GlassRow(symbol: "power", tint: .blue, title: L("Запускать при входе в систему")) {
                    GlassSwitch(isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                }
                if launchAtLogin.needsApproval {
                    GlassRow(symbol: "exclamationmark.triangle", tint: .orange,
                             title: L("Разрешите Shotty в «Системных настройках» → «Основные» → «Объекты входа».")) {
                        GlassButton(title: L("Открыть")) { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let error = launchAtLogin.error {
                    GlassRow(symbol: "xmark.octagon", tint: .red, title: error) { EmptyView() }
                }
                GlassRow(symbol: "globe", tint: .green, title: L("Язык")) {
                    GlassSegmented(options: AppLanguage.allCases, selection: $preferences.language,
                                   title: \.title, itemWidth: 84)
                }
                GlassRow(symbol: "circle.lefthalf.filled", tint: .purple, title: L("Оформление"), showsDivider: false) {
                    GlassSegmented(options: AppTheme.allCases, selection: $preferences.theme, title: \.title)
                }
            }

            GlassSection(L("Горячие клавиши"), trailing: 10) {
                ForEach(HotKeyAction.allCases) { action in
                    GlassRow(symbol: action.settingsSymbol, tint: action.settingsTint,
                             title: action.settingsTitle, detail: action.settingsDetail, height: 42,
                             showsDivider: action != HotKeyAction.allCases.last) {
                        HotKeyRecorder(action: action)
                    }
                }
            } footer: {
                VStack(alignment: .trailing, spacing: 10) {
                    Text(L("Нажмите на поле и введите новое сочетание. Нужна хотя бы одна из клавиш ⌘, ⌥ или ⌃ (F1–F20 можно без них). Esc — отмена, ⌫ — отключить. Сочетания работают в любой программе."))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GlassButton(title: L("Вернуть сочетания по умолчанию"), symbol: "arrow.counterclockwise", large: true) {
                        hotKeys.resetToDefaults()
                    }
                    // The button lines up with the card, not with the indented note.
                    .padding(.trailing, -8)
                }
            }

            RecordingSettingsSection()
        }
        .onAppear { launchAtLogin.refresh() }
    }
}

struct RecordingSettingsSection: View {
    @ObservedObject private var settings = RecordingSettings.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GlassSection(L("Запись видео")) {
            GlassRow(symbol: "speaker.wave.2", tint: .blue, title: L("Звук с экрана"), detail: L("системный звук")) {
                GlassSwitch(isOn: $settings.recordSystemAudio)
            }
            GlassRow(symbol: "mic", tint: .green, title: L("Звук с микрофона")) {
                GlassSwitch(isOn: $settings.recordMicrophone)
            }
            GlassRow(symbol: "cursorarrow", tint: .orange, title: L("Показывать курсор")) {
                GlassSwitch(isOn: $settings.showCursor)
            }
            GlassRow(symbol: "folder", tint: .purple, title: L("Сохранять в"), showsDivider: false) {
                HStack(spacing: 10) {
                    Text(settings.folderDisplay)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsStyle.secondary(scheme))
                        .lineLimit(1).truncationMode(.middle)
                    GlassButton(title: L("Выбрать…")) { settings.chooseFolder() }
                }
            }
        } footer: {
            Text(L("Нажмите сочетание записи — появится панель, где можно выбрать весь экран или область и включить звук и микрофон. Во время записи доступны пауза и завершение; повторное нажатие сочетания тоже завершает запись. После записи видео можно сохранить или загрузить на сервер. «Сохранить» кладёт видео в эту папку."))
        }
    }
}

struct HotKeyRecorder: View {
    let action: HotKeyAction
    @ObservedObject private var hotKeys = HotKeySettings.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    recording ? stopRecording() : startRecording()
                } label: {
                    field
                }
                .buttonStyle(.hand(.plain))
                .onHover { hovering = $0 }
                .help(recording ? L("Отмена") : L("Изменить"))

                Button {
                    hotKeys.set(nil, for: action)
                    message = nil
                    stopRecording()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SettingsStyle.detail(scheme))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.hand(.plain))
                .help(L("Отключить сочетание"))
                .opacity(hotKeys.hotKey(for: action) == nil && !recording ? 0 : 1)
                .disabled(hotKeys.hotKey(for: action) == nil && !recording)
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            } else if hotKeys.failedActions.contains(action) {
                Text(L("Сочетание занято другой программой — выберите другое"))
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, message != nil || hotKeys.failedActions.contains(action) ? 6 : 0)
        .onDisappear { stopRecording() }
    }

    private var field: some View {
        let key = hotKeys.hotKey(for: action)
        let dark = scheme == .dark
        let shape = Capsule()
        let text = recording ? L("Нажмите сочетание…") : (key?.displayString ?? L("+ Задать"))
        return Text(text)
            .font(.system(size: recording ? 11 : 12, weight: key == nil || recording ? .medium : .semibold))
            .tracking(key == nil || recording ? 0 : 0.48)
            .foregroundStyle(recording ? (dark ? Glass.hex(0xCFE0FF) : Glass.hex(0x1F4F9A))
                                       : (key == nil ? SettingsStyle.secondary(scheme) : SettingsStyle.primary(scheme)))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: 128, height: 28)
            .background {
                if recording {
                    ZStack {
                        shape.inset(by: -3).fill(dark ? Glass.hex(0x3A6BFF, 0.18) : Glass.hex(0x2F62E8, 0.18))
                        shape.fill(dark ? Glass.hex(0x3A6BFF, 0.18) : Color.white.opacity(0.85))
                            .overlay(shape.strokeBorder(SettingsStyle.focus(scheme), lineWidth: 1))
                    }
                    .shadow(color: dark ? Glass.hex(0x3A6BFF, 0.35) : .clear, radius: 9)
                } else if key == nil {
                    shape.strokeBorder(dark ? Color.white.opacity(0.28) : Glass.hex(0x102A54, 0.3),
                                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else {
                    shape.fill(dark ? Color.white.opacity(hovering ? 0.14 : 0.08) : Color.white.opacity(hovering ? 0.85 : 0.7))
                        .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.16) : Color.white.opacity(0.7), lineWidth: 0.5))
                        .shadow(color: dark ? .clear : SettingsStyle.smallShadow, radius: 1.5, y: 1)
                }
            }
            .contentShape(shape)
    }

    private func startRecording() {
        message = nil
        recording = true
        hotKeys.beginRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hotKeys.endRecording()
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = UInt32(event.keyCode)

        if flags.isEmpty && keyCode == UInt32(kVK_Escape) {
            stopRecording()
            return
        }
        if flags.isEmpty && (keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete)) {
            hotKeys.set(nil, for: action)
            stopRecording()
            return
        }
        guard KeyNames.isKnown(keyCode) else {
            message = L("Эту клавишу нельзя использовать")
            return
        }
        let hasRequiredModifier = !flags.intersection([.command, .option, .control]).isEmpty
        guard hasRequiredModifier || KeyNames.isFunctionKey(keyCode) else {
            message = L("Добавьте ⌘, ⌥ или ⌃")
            return
        }
        let key = HotKey(keyCode: keyCode, modifiers: HotKey.carbonModifiers(from: flags))
        if Self.isReservedBySystem(key) {
            message = L("%@ занято системными снимками macOS", key.displayString)
            return
        }
        if let other = hotKeys.action(using: key, except: action) {
            message = L("%@ уже используется: «%@»", key.displayString, other.title)
            return
        }
        message = nil
        hotKeys.set(key, for: action)
        stopRecording()
    }

    private static func isReservedBySystem(_ key: HotKey) -> Bool {
        let cmdShift = UInt32(cmdKey | shiftKey)
        let ctrlCmdShift = UInt32(cmdKey | shiftKey | controlKey)
        let screenshotKeys: Set<Int> = [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
        return (key.modifiers == cmdShift || key.modifiers == ctrlCmdShift) && screenshotKeys.contains(Int(key.keyCode))
    }
}
