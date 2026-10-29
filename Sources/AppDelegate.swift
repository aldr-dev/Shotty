import AppKit
import AVFoundation
import Combine
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var serverMenu = NSMenu()
    private var systemAudioItem: NSMenuItem?
    private var microphoneItem: NSMenuItem?
    private var darkModeItem: NSMenuItem?
    private var homeWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var editors: [EditorWindowController] = []
    private var isCapturing = false
    private var actionMenuItems: [(HotKeyAction, NSMenuItem)] = []
    private var elapsedObserver: AnyCancellable?
    private var resultWindows: [RecordingResultWindowController] = []

    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPreferences.shared.applyTheme()
        LaunchAtLogin.shared.enableOnFirstLaunch()
        NSApp.mainMenu = buildMainMenu()
        setupStatusItem()
        NotificationCenter.default.addObserver(forName: AppPreferences.languageDidChange, object: nil, queue: .main) { [weak self] _ in
            // Deferred so menus aren't rebuilt from inside the click that changed the language.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.languageChanged() } }
        }
        HotKeySettings.shared.onChange = { [weak self] in self?.applyHotKeys() }
        ScreenRecorder.shared.onStateChange = { [weak self] state in self?.recorderStateChanged(state) }
        applyHotKeys()
        showHome(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showHome(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ScreenRecorder.shared.isActive else { return .terminateNow }
        // Finish the recording first so the user can decide what to do with it.
        ScreenRecorder.shared.stop()
        return .terminateCancel
    }

    // MARK: - Capture

    @objc func captureArea(_ sender: Any?) { startCapture(.area) }
    @objc func captureWindow(_ sender: Any?) { startCapture(.window) }
    @objc func captureFullScreen(_ sender: Any?) { startCapture(.fullScreen) }

    func startCapture(_ mode: CaptureMode) {
        runCapture(mode) { [weak self] image in self?.openEditor(with: image) }
    }

    private func runCapture(_ mode: CaptureMode, onImage: @escaping (NSImage) -> Void) {
        guard !isCapturing else { return }
        guard CaptureService.hasPermission() else {
            showPermissionAlert()
            return
        }
        isCapturing = true
        let homeWasVisible = homeWindow?.isVisible ?? false
        homeWindow?.orderOut(nil)
        if mode == .fullScreen { NSApp.hide(nil) }

        DispatchQueue.main.asyncAfter(deadline: .now() + (mode == .fullScreen ? 0.4 : 0.15)) {
            CaptureService.capture(mode) { [weak self] image in
                guard let self else { return }
                self.isCapturing = false
                if let image {
                    onImage(image)
                } else {
                    if mode == .fullScreen { NSApp.unhide(nil) }
                    if homeWasVisible { self.showHome(nil) }
                }
            }
        }
    }

    func openEditor(with image: NSImage) {
        let editor = EditorWindowController(image: image)
        editor.onClose = { [weak self] controller in
            self?.editors.removeAll { $0 === controller }
        }
        editors.append(editor)
        NSApp.unhide(nil)
        editor.showWindow(nil)
        bringToFront(editor.window)
    }

    /// Puts the window above every other app's windows, even when macOS declines to activate us.
    private func bringToFront(_ window: NSWindow?) {
        guard let window else { return }
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        // Back to normal so it doesn't stay pinned above other apps.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { window.level = .normal }
    }

    // MARK: - Text recognition

    @objc func recognizeText(_ sender: Any?) {
        runCapture(.area) { image in
            Task { @MainActor in
                do {
                    let text = try await TextRecognizer.recognize(image)
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HUD.show(L("Текст не найден"), symbol: "text.viewfinder", isError: true)
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        HUD.show(L("Текст скопирован в буфер обмена (%ld симв.)", text.count), symbol: "doc.on.clipboard.fill")
                    }
                } catch {
                    HUD.show(L("Не удалось распознать текст: %@", error.localizedDescription),
                             symbol: "exclamationmark.triangle.fill", isError: true)
                }
            }
        }
    }

    // MARK: - Video recording

    @objc func toggleRecording(_ sender: Any?) {
        switch ScreenRecorder.shared.state {
        case .recording, .paused: ScreenRecorder.shared.stop()
        case .idle: Countdown.isActive ? Countdown.cancel() : showRecordingSetup()
        case .finishing: break
        }
    }

    private func showRecordingSetup() {
        guard !isCapturing, !RecordingSetup.isActive else { return }
        guard CaptureService.hasPermission() else {
            showPermissionAlert()
            return
        }
        isCapturing = true
        let previousApp = NSWorkspace.shared.frontmostApplication
        homeWindow?.orderOut(nil)
        RecordingSetup.begin { [weak self] selection in
            guard let self else { return }
            self.isCapturing = false
            if let previousApp, previousApp != NSRunningApplication.current { previousApp.activate() }
            guard let selection else { return }
            Task { @MainActor in await self.startRecording(selection) }
        }
    }

    @MainActor
    private func startRecording(_ selection: RegionSelection) async {
        let settings = RecordingSettings.shared
        var microphone = settings.recordMicrophone
        if microphone, await !Self.microphoneAccess() {
            microphone = false
            HUD.show(L("Нет доступа к микрофону — запись без него. Разрешите доступ в «Системных настройках» → «Конфиденциальность» → «Микрофон»."),
                     symbol: "mic.slash.fill", isError: true)
        }
        let options = RecordingOptions(selection: selection, systemAudio: settings.recordSystemAudio,
                                       microphone: microphone, showCursor: settings.showCursor)
        let proceed = await withCheckedContinuation { continuation in
            Countdown.run(on: selection.screen) { continuation.resume(returning: $0) }
        }
        guard proceed else { return }
        do {
            try await ScreenRecorder.shared.start(options) { [weak self] result in
                switch result {
                case .success(let url):
                    self?.openRecordingResult(url)
                case .failure(let error):
                    HUD.show(L("Ошибка записи: %@", error.localizedDescription), symbol: "exclamationmark.triangle.fill", isError: true)
                }
            }
            RecordingControls.shared.show(for: selection)
        } catch {
            HUD.show(L("Не удалось начать запись: %@", error.localizedDescription),
                     symbol: "exclamationmark.triangle.fill", isError: true)
        }
    }

    private func openRecordingResult(_ url: URL) {
        let controller = RecordingResultWindowController(fileURL: url)
        controller.onClose = { [weak self] closed in self?.resultWindows.removeAll { $0 === closed } }
        resultWindows.append(controller)
        controller.showWindow(nil)
        bringToFront(controller.window)
    }

    private static func microphoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private func recorderStateChanged(_ state: ScreenRecorder.State) {
        guard let item = statusItem, let button = item.button else { return }
        switch state {
        case .recording, .paused:
            let paused = state == .paused
            item.menu = nil
            button.target = self
            button.action = #selector(toggleRecording(_:))
            button.image = NSImage(systemSymbolName: paused ? "pause.circle.fill" : "stop.circle.fill",
                                   accessibilityDescription: L("Завершить запись"))
            button.contentTintColor = paused ? .systemOrange : .systemRed
            button.imagePosition = .imageLeading
            button.toolTip = L("Завершить запись")
            if elapsedObserver == nil {
                elapsedObserver = ScreenRecorder.shared.$elapsed
                    .map { Int($0) }
                    .removeDuplicates()
                    .receive(on: RunLoop.main)
                    .sink { [weak button] seconds in
                        button?.attributedTitle = NSAttributedString(
                            string: " " + RecordingControlsView.format(TimeInterval(seconds)),
                            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
                    }
            }
        case .finishing:
            RecordingControls.shared.hide()
        case .idle:
            RecordingControls.shared.hide()
            elapsedObserver = nil
            item.menu = statusMenu
            button.action = nil
            button.title = ""
            button.contentTintColor = nil
            button.toolTip = nil
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shotty")
            image?.isTemplate = true
            button.image = image
        }
        for (action, menuItem) in actionMenuItems where action == .record {
            menuItem.title = ScreenRecorder.shared.isActive ? L("Завершить запись") : action.title
        }
    }

    @objc private func toggleSystemAudio(_ sender: Any?) { RecordingSettings.shared.recordSystemAudio.toggle() }
    @objc private func toggleMicrophone(_ sender: Any?) { RecordingSettings.shared.recordMicrophone.toggle() }

    // MARK: - Servers

    @objc func switchServer(_ sender: Any?) {
        let settings = ServerSettings.shared
        guard let next = settings.selectNextServer() else {
            HUD.show(L("Нет настроенных серверов"), symbol: "server.rack", isError: true)
            return
        }
        let count = settings.servers.filter(\.isConfigured).count
        HUD.show(L("Загрузка на: %@", next.displayName) + (count > 1 ? L(Self.serverCountKey(count), count) : ""), symbol: "server.rack")
    }

    /// Russian plural form: 1 сервер, 2 сервера, 5 серверов (21 сервер, 22 сервера, 11 серверов).
    private static func serverCountKey(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "  (%ld сервер)" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "  (%ld сервера)" }
        return "  (%ld серверов)"
    }

    @objc private func selectServer(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        ServerSettings.shared.activeID = id
    }

    @objc private func openServerSettings(_ sender: Any?) { showSettings(tab: .server) }

    private func rebuildServerMenu() {
        let settings = ServerSettings.shared
        serverMenu.removeAllItems()
        for server in settings.servers where server.isConfigured {
            let item = NSMenuItem(title: server.displayName, action: #selector(selectServer(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = server.id
            item.state = server.id == settings.active?.id ? .on : .off
            item.toolTip = server.summary
            serverMenu.addItem(item)
        }
        if serverMenu.items.isEmpty {
            let empty = NSMenuItem(title: L("Нет настроенных серверов"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            serverMenu.addItem(empty)
        }
        serverMenu.addItem(.separator())
        serverMenu.addItem(menuItem(L("Настроить серверы…"), #selector(openServerSettings(_:)), "", [], symbol: "plus.circle"))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === serverMenu { rebuildServerMenu() }
        if menu === statusMenu {
            systemAudioItem?.state = RecordingSettings.shared.recordSystemAudio ? .on : .off
            microphoneItem?.state = RecordingSettings.shared.recordMicrophone ? .on : .off
            darkModeItem?.state = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .on : .off
        }
    }

    // MARK: - Permissions

    private func showPermissionAlert() {
        CaptureService.requestPermission()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Нужен доступ к записи экрана")
        alert.informativeText = L("Откройте «Системные настройки» → «Конфиденциальность и безопасность» → «Запись экрана и системного аудио» и включите «Shotty». Если Shotty там уже включён, но доступ всё равно не работает — удалите его из списка кнопкой «−» и добавьте снова.\n\nmacOS применяет разрешение только после перезапуска приложения.")
        alert.addButton(withTitle: L("Открыть настройки"))
        alert.addButton(withTitle: L("Перезапустить Shotty"))
        alert.addButton(withTitle: L("Позже"))
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
    }

    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.7; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Windows

    @objc func showHome(_ sender: Any?) {
        if homeWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.title = "Shotty"

            let effect = NSVisualEffectView()
            effect.material = .underWindowBackground
            effect.blendingMode = .behindWindow
            effect.state = .active
            let hosting = NSHostingView(rootView: Localized {
                HomeView(onAction: { [weak self] action in self?.perform(action) },
                         onSettings: { [weak self] tab in self?.showSettings(tab: tab) })
            })
            // Window size is set explicitly; letting SwiftUI drive it crashes on appearance changes.
            hosting.sizingOptions = []
            hosting.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: effect.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            window.contentView = effect
            window.setContentSize(homeContentSize())
            window.center()
            WindowButtons.keepColored(window)
            homeWindow = window
        }
        NSApp.unhide(nil)
        bringToFront(homeWindow)
    }

    private func homeContentSize() -> NSSize {
        NSHostingController(rootView: HomeView(onAction: { _ in }, onSettings: { _ in }))
            .sizeThatFits(in: NSSize(width: 600, height: 2000))
    }

    @objc func showSettings(_ sender: Any?) { showSettings(tab: .general) }

    func showSettings(tab: SettingsTab) {
        SettingsNavigation.shared.tab = tab
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 720),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.title = L("Настройки Shotty")
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: Localized { SettingsRootView() })
            hosting.sizingOptions = []
            window.contentView = hosting
            window.center()
            WindowButtons.keepColored(window)
            settingsWindow = window
        }
        NSApp.unhide(nil)
        bringToFront(settingsWindow)
    }

    // MARK: - Hot keys

    func perform(_ action: HotKeyAction) {
        switch action {
        case .area: startCapture(.area)
        case .window: startCapture(.window)
        case .fullScreen: startCapture(.fullScreen)
        case .ocr: recognizeText(nil)
        case .record: toggleRecording(nil)
        case .switchServer: switchServer(nil)
        }
    }

    private func applyHotKeys() {
        let settings = HotKeySettings.shared
        HotKeyManager.shared.unregisterAll()
        var failed: Set<HotKeyAction> = []
        for action in HotKeyAction.allCases {
            guard let key = settings.hotKey(for: action) else { continue }
            let ok = HotKeyManager.shared.register(id: action.carbonID, hotKey: key) { [weak self] in
                self?.perform(action)
            }
            if !ok { failed.insert(action) }
        }
        settings.failedActions = failed

        for (action, item) in actionMenuItems {
            if let key = settings.hotKey(for: action) {
                item.keyEquivalent = KeyNames.menuKeyEquivalent(for: key.keyCode)
                item.keyEquivalentModifierMask = key.menuModifierFlags
            } else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }
        }
    }

    private func actionItem(_ action: HotKeyAction, symbol: Bool) -> NSMenuItem {
        let selector: Selector
        switch action {
        case .area: selector = #selector(captureArea(_:))
        case .window: selector = #selector(captureWindow(_:))
        case .fullScreen: selector = #selector(captureFullScreen(_:))
        case .ocr: selector = #selector(recognizeText(_:))
        case .record: selector = #selector(toggleRecording(_:))
        case .switchServer: selector = #selector(switchServer(_:))
        }
        let item = menuItem(action.title, selector, "", [], symbol: symbol ? action.symbol : nil)
        actionMenuItems.append((action, item))
        return item
    }

    // MARK: - Menus

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shotty")
            image?.isTemplate = true
            button.image = image
        }
        statusItem = item
        buildStatusMenu()
    }

    private func buildStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self
        for action in HotKeyAction.captureActions { menu.addItem(actionItem(action, symbol: true)) }
        menu.addItem(actionItem(.ocr, symbol: true))
        menu.addItem(.separator())
        menu.addItem(actionItem(.record, symbol: true))
        let systemAudio = menuItem(L("Звук с экрана"), #selector(toggleSystemAudio(_:)), "", [], symbol: "speaker.wave.2")
        menu.addItem(systemAudio)
        systemAudioItem = systemAudio
        let microphone = menuItem(L("Микрофон"), #selector(toggleMicrophone(_:)), "", [], symbol: "mic")
        menu.addItem(microphone)
        microphoneItem = microphone
        menu.addItem(.separator())

        serverMenu = NSMenu(title: L("Сервер для загрузки"))
        serverMenu.delegate = self
        let serverItem = NSMenuItem(title: L("Сервер для загрузки"), action: nil, keyEquivalent: "")
        serverItem.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil)
        serverItem.submenu = serverMenu
        menu.addItem(serverItem)
        menu.addItem(actionItem(.switchServer, symbol: true))
        menu.addItem(.separator())
        let darkMode = menuItem(L("Тёмная тема"), #selector(toggleDarkMode(_:)), "", [], symbol: "moon")
        menu.addItem(darkMode)
        darkModeItem = darkMode
        let languageItem = NSMenuItem(title: L("Язык"), action: nil, keyEquivalent: "")
        languageItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = menuItem(language.title, #selector(selectLanguage(_:)), "", [])
            item.representedObject = language.rawValue
            item.state = language == AppPreferences.shared.language ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(L("Открыть Shotty"), #selector(showHome(_:)), "", [], symbol: "macwindow.on.rectangle"))
        menu.addItem(menuItem(L("Настройки…"), #selector(showSettings(_:)), ",", [.command], symbol: "gearshape"))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("Завершить Shotty"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusMenu = menu
        if !ScreenRecorder.shared.isActive { statusItem?.menu = menu }
    }

    // MARK: - Appearance & language

    @objc private func toggleDarkMode(_ sender: Any?) { AppPreferences.shared.toggleDarkMode() }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        AppPreferences.shared.language = language
    }

    private func languageChanged() {
        actionMenuItems.removeAll()
        NSApp.mainMenu = buildMainMenu()
        buildStatusMenu()
        applyHotKeys()
        recorderStateChanged(ScreenRecorder.shared.state)
        settingsWindow?.title = L("Настройки Shotty")
        DispatchQueue.main.async { [weak self] in
            guard let self, let home = self.homeWindow else { return }
            home.setContentSize(self.homeContentSize())
        }
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags, symbol: String? = nil, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = target ?? self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("О программе Shotty"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(L("Настройки…"), #selector(showSettings(_:)), ",", [.command]))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Скрыть Shotty"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: L("Скрыть остальные"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Завершить Shotty"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, title: "Shotty", to: main)

        let fileMenu = NSMenu(title: L("Файл"))
        for action in HotKeyAction.allCases { fileMenu.addItem(actionItem(action, symbol: false)) }
        fileMenu.addItem(.separator())
        let save = NSMenuItem(title: L("Сохранить как…"), action: #selector(EditorWindowController.saveImage(_:)), keyEquivalent: "s")
        fileMenu.addItem(save)
        let upload = NSMenuItem(title: L("Загрузить на сервер"), action: #selector(EditorWindowController.uploadImage(_:)), keyEquivalent: "u")
        fileMenu.addItem(upload)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: L("Закрыть"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(fileMenu, title: L("Файл"), to: main)

        let editMenu = NSMenu(title: L("Правка"))
        editMenu.addItem(withTitle: L("Отменить"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L("Повторить"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Вырезать"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Копировать"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Вставить"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Удалить"), action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: L("Выбрать все"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(editMenu, title: L("Правка"), to: main)

        let windowMenu = NSMenu(title: L("Окно"))
        windowMenu.addItem(withTitle: L("Свернуть"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L("Масштаб"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(menuItem(L("Главное окно"), #selector(showHome(_:)), "0", [.command]))
        addSubmenu(windowMenu, title: L("Окно"), to: main)
        NSApp.windowsMenu = windowMenu

        return main
    }

    private func addSubmenu(_ submenu: NSMenu, title: String, to main: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}
