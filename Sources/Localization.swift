import AppKit
import ServiceManagement
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru, en
    var id: String { rawValue }
    var title: String { self == .ru ? "Русский" : "English" }
    var locale: Locale { Locale(identifier: self == .ru ? "ru_RU" : "en_US") }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("Как в системе")
        case .light: L("Светлая")
        case .dark: L("Тёмная")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Starts Shotty at login so hot keys work right after the Mac boots.
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()
    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var error: String?

    private init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    /// Turned on once by default; after that the user's choice in Settings is kept.
    func enableOnFirstLaunch() {
        let key = "launchAtLogin.initialized"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }
}

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    static let languageDidChange = Notification.Name("ShottyLanguageDidChange")
    private let defaults = UserDefaults.standard

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "ui.language")
            NotificationCenter.default.post(name: Self.languageDidChange, object: nil)
        }
    }

    @Published var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: "ui.theme")
            applyTheme()
        }
    }

    private init() {
        let systemIsRussian = Locale.preferredLanguages.first?.hasPrefix("ru") ?? true
        language = AppLanguage(rawValue: defaults.string(forKey: "ui.language") ?? "") ?? (systemIsRussian ? .ru : .en)
        theme = AppTheme(rawValue: defaults.string(forKey: "ui.theme") ?? "") ?? .system
    }

    func applyTheme() {
        // Deferred so the switch never happens inside menu tracking or a layout pass.
        let appearance = theme.appearance
        DispatchQueue.main.async { NSApp.appearance = appearance }
    }

    /// Quick toggle between light and dark, starting from whatever is currently shown.
    func toggleDarkMode() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        theme = isDark ? .light : .dark
    }
}

/// Re-creates its content when the language changes so every `L(...)` is evaluated again.
struct Localized<Content: View>: View {
    @ObservedObject private var preferences = AppPreferences.shared
    private let content: Content

    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View { content.id(preferences.language) }
}

/// Translates a Russian UI string (the key) into the current interface language.
func L(_ key: String) -> String {
    guard AppPreferences.shared.language == .en else { return key }
    return englishStrings[key] ?? key
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

private let englishStrings: [String: String] = [
    // Interface & theme
    "Интерфейс": "Interface",
    "Запускать при входе в систему": "Launch at login",
    "Разрешите Shotty в «Системных настройках» → «Основные» → «Объекты входа».": "Allow Shotty in System Settings → General → Login Items.",
    "Открыть": "Open",
    "Язык": "Language",
    "Оформление": "Appearance",
    "Как в системе": "System",
    "Светлая": "Light",
    "Тёмная": "Dark",
    "Тёмная тема": "Dark Mode",
    "Сменить язык": "Change language",
    "Переключить тёмную тему": "Toggle dark mode",

    // Home
    "Снимки экрана, стрелки, рамки, текст и загрузка на сервер": "Screenshots, arrows, frames, text and server upload",
    "Область": "Area",
    "Окно": "Window",
    "Весь экран": "Full Screen",
    "Текст из области": "Text from Area",
    "Запись видео": "Record Video",
    "Сервер не настроен": "No server configured",
    "Укажите FTP или SFTP, чтобы загружать снимки": "Set up FTP or SFTP to upload screenshots",
    "Сменить": "Switch",
    "Настроить…": "Configure…",
    "Горячие клавиши": "Keyboard Shortcuts",
    "без сочетания": "no shortcut",
    "Выбрать сервер для загрузки": "Choose upload server",

    // Hot keys
    "Снимок области": "Capture Area",
    "Снимок окна": "Capture Window",
    "Снимок всего экрана": "Capture Full Screen",
    "Распознать текст": "Recognize Text",
    "Запись видео (старт/стоп)": "Record Video (start/stop)",
    "Сменить сервер загрузки": "Switch Upload Server",
    "Не задано": "Not set",
    "Нажмите «Изменить», затем новое сочетание. Нужна хотя бы одна из клавиш ⌘, ⌥ или ⌃ (F1–F20 можно без них). Esc — отмена, ⌫ — отключить сочетание. Сочетания работают в любой программе.":
        "Click “Change”, then press a new shortcut. It needs at least one of ⌘, ⌥ or ⌃ (F1–F20 work alone). Esc cancels, ⌫ disables the shortcut. Shortcuts work in any app.",
    "Вернуть сочетания по умолчанию": "Restore Default Shortcuts",
    "Нажмите сочетание…": "Press shortcut…",
    "Отмена": "Cancel",
    "Изменить": "Change",
    "Отключить сочетание": "Disable shortcut",
    "Сочетание занято другой программой — выберите другое": "Shortcut is taken by another app — choose another",
    "Эту клавишу нельзя использовать": "This key can't be used",
    "Добавьте ⌘, ⌥ или ⌃": "Add ⌘, ⌥ or ⌃",
    "%@ занято системными снимками macOS": "%@ is reserved for macOS screenshots",
    "%@ уже используется: «%@»": "%@ is already used by “%@”",
    "Клавиша %ld": "Key %ld",
    "Пробел": "Space",

    // Recording settings
    "Звук с экрана (системный звук)": "Screen audio (system sound)",
    "Звук с микрофона": "Microphone audio",
    "Показывать курсор": "Show cursor",
    "Сохранять в": "Save to",
    "Выбрать…": "Choose…",
    "Выбрать": "Choose",
    "Нажмите сочетание записи — появится панель, где можно выбрать весь экран или область и включить звук и микрофон. Во время записи доступны пауза и завершение; повторное нажатие сочетания тоже завершает запись. После записи видео можно сохранить или загрузить на сервер. «Сохранить» кладёт видео в эту папку.":
        "Press the recording shortcut — a toolbar appears where you choose full screen or an area and turn audio and microphone on or off. While recording you can pause and stop; pressing the shortcut again also stops. Afterwards the video can be saved or uploaded to a server. “Save” puts it in this folder.",

    // Settings: servers
    "Основные": "General",
    "Серверы": "Servers",
    "Настройки Shotty": "Shotty Settings",
    "Добавить сервер": "Add server",
    "Удалить выбранный сервер": "Remove selected server",
    "Отметьте кружком сервер, на который будут загружаться снимки. Переключать серверы можно горячей клавишей (см. «Основные») или из меню Shotty в строке меню.":
        "Mark the server that uploads go to with the circle. You can switch servers with a shortcut (see “General”) or from the Shotty menu bar menu.",
    "Копировать ссылку после загрузки": "Copy link after upload",
    "Сюда загружаются снимки": "Uploads go here",
    "Загружать снимки на этот сервер": "Upload to this server",
    "для загрузки": "for uploads",
    "Название": "Name",
    "например, Рабочий": "e.g. Work",
    "Протокол": "Protocol",
    "Сервер": "Server",
    "Порт": "Port",
    "Пользователь": "User",
    "Пароль": "Password",
    "хранится в Связке ключей": "stored in Keychain",
    "SSH-ключ": "SSH key",
    "необязательно, ~/.ssh/id_ed25519": "optional, ~/.ssh/id_ed25519",
    "Активный режим (PORT)": "Active mode (PORT)",
    "Не проверять сертификат сервера": "Don't verify server certificate",
    "Подключение — %@": "Connection — %@",
    "Папка на сервере": "Remote folder",
    "Публичный URL папки": "Public folder URL",
    "Размещение файлов": "File Location",
    "Если папки нет — она будет создана. Публичный URL нужен, чтобы после загрузки получить готовую ссылку на картинку.":
        "The folder is created if missing. The public URL is used to build a ready link to the file after upload.",
    "Проверить подключение": "Test Connection",
    "Подключение успешно": "Connection successful",
    "Обычный FTP без шифрования. Путь указывается относительно домашней папки пользователя.":
        "Plain FTP without encryption. The path is relative to the user's home folder.",
    "FTP с шифрованием TLS (explicit, AUTH TLS). Путь указывается относительно домашней папки пользователя.":
        "FTP with TLS encryption (explicit, AUTH TLS). The path is relative to the user's home folder.",
    "Передача файлов по SSH. Можно войти по паролю или по SSH-ключу. Путь, начинающийся с «/», считается абсолютным.":
        "File transfer over SSH. Log in with a password or an SSH key. A path starting with “/” is absolute.",
    "Новый сервер": "New server",
    "адрес не указан": "no address",
    "Shotty — пароль сервера": "Shotty — server password",

    // Upload errors
    "Вход выполнен, но папка «%@» не найдена. Она будет создана при первой загрузке.":
        "Logged in, but folder “%@” wasn't found. It will be created on first upload.",
    "Не удалось найти сервер (проверьте адрес)": "Server not found (check the address)",
    "Не удалось подключиться к серверу (проверьте адрес и порт)": "Couldn't connect to the server (check address and port)",
    "Сервер отказал в доступе к папке": "The server denied access to the folder",
    "Превышено время ожидания": "Timed out",
    "Ошибка TLS/сертификата. Попробуйте включить «Не проверять сертификат»": "TLS/certificate error. Try enabling “Don't verify server certificate”",
    "Сервер не поддерживает FTPS (TLS)": "The server doesn't support FTPS (TLS)",
    "Неверный логин или пароль": "Wrong login or password",
    "Сервер не принял файл (нет прав на запись?)": "The server rejected the file (no write permission?)",
    "Ошибка curl %d": "curl error %d",
    "Неверный логин, пароль или ключ": "Wrong login, password or key",
    "Сервер отклонил подключение (проверьте порт)": "The server refused the connection (check the port)",
    "Ключ сервера изменился. Проверьте ~/.ssh/known_hosts": "The server key changed. Check ~/.ssh/known_hosts",
    "Папка на сервере не найдена": "Remote folder not found",
    "Ошибка SFTP (код %d)": "SFTP error (code %d)",

    // App menus & alerts
    "О программе Shotty": "About Shotty",
    "Настройки…": "Settings…",
    "Скрыть Shotty": "Hide Shotty",
    "Скрыть остальные": "Hide Others",
    "Завершить Shotty": "Quit Shotty",
    "Файл": "File",
    "Сохранить как…": "Save As…",
    "Загрузить на сервер": "Upload to Server",
    "Закрыть": "Close",
    "Правка": "Edit",
    "Отменить": "Undo",
    "Повторить": "Redo",
    "Вырезать": "Cut",
    "Копировать": "Copy",
    "Вставить": "Paste",
    "Удалить": "Delete",
    "Выбрать все": "Select All",
    "Свернуть": "Minimize",
    "Масштаб": "Zoom",
    "Главное окно": "Main Window",
    "Открыть Shotty": "Open Shotty",
    "Звук с экрана": "Screen Audio",
    "Микрофон": "Microphone",
    "Сервер для загрузки": "Upload Server",
    "Нет настроенных серверов": "No servers configured",
    "Настроить серверы…": "Configure Servers…",
    "Завершить запись": "Stop Recording",
    "Нужен доступ к записи экрана": "Screen recording access required",
    "Откройте «Системные настройки» → «Конфиденциальность и безопасность» → «Запись экрана и системного аудио» и включите «Shotty». Если Shotty там уже включён, но доступ всё равно не работает — удалите его из списка кнопкой «−» и добавьте снова.\n\nmacOS применяет разрешение только после перезапуска приложения.":
        "Open System Settings → Privacy & Security → Screen & System Audio Recording and enable “Shotty”. If it's already enabled but still doesn't work, remove it with “−” and add it again.\n\nmacOS applies the permission only after the app restarts.",
    "Открыть настройки": "Open Settings",
    "Перезапустить Shotty": "Restart Shotty",
    "Позже": "Later",
    "Текст не найден": "No text found",
    "Текст скопирован в буфер обмена (%ld симв.)": "Text copied to clipboard (%ld chars)",
    "Не удалось распознать текст: %@": "Couldn't recognize text: %@",
    "Нет доступа к микрофону — запись без него. Разрешите доступ в «Системных настройках» → «Конфиденциальность» → «Микрофон».":
        "No microphone access — recording without it. Allow access in System Settings → Privacy → Microphone.",
    "Ошибка записи: %@": "Recording error: %@",
    "Не удалось начать запись: %@": "Couldn't start recording: %@",
    "Не удалось продолжить запись: %@": "Couldn't resume recording: %@",
    "Загрузка на: %@": "Uploading to: %@",
    "  (%ld сервер)": "  (%ld servers)",
    "  (%ld сервера)": "  (%ld servers)",
    "  (%ld серверов)": "  (%ld servers)",

    // Editor
    "Выбор и перемещение (V)": "Select and Move (V)",
    "Стрелка (A)": "Arrow (A)",
    "Цветная рамка (R)": "Rectangle (R)",
    "Текст (T)": "Text (T)",
    "Маркер (H)": "Highlighter (H)",
    "Эмодзи — растягивается за ручки (E)": "Emoji — drag the handles to stretch (E)",
    "Эмодзи": "Emoji",
    "Смайлики": "Smileys & Emotion",
    "Люди и жесты": "People & Body",
    "Животные и природа": "Animals & Nature",
    "Еда и напитки": "Food & Drink",
    "Активность": "Activities",
    "Путешествия и места": "Travel & Places",
    "Предметы": "Objects",
    "Символы": "Symbols",
    "Флаги": "Flags",
    "Недавние": "Frequently Used",
    "Поиск эмодзи": "Search emoji",
    "Ничего не найдено": "Nothing found",
    "Выберите эмодзи и кликните по скриншоту — или протяните рамку нужного размера": "Pick an emoji and click the screenshot — or drag a box of the size you want",
    "Размытие — скрыть пароли, почту, токены (B)": "Blur — hide passwords, emails, tokens (B)",
    "Пикселизация — скрыть пароли, почту, токены (P)": "Pixelate — hide passwords, emails, tokens (P)",
    "Текст": "Text",
    "Красный": "Red",
    "Оранжевый": "Orange",
    "Жёлтый": "Yellow",
    "Зелёный": "Green",
    "Синий": "Blue",
    "Фиолетовый": "Purple",
    "Белый": "White",
    "Чёрный": "Black",
    "Цвет": "Color",
    "Другой цвет": "Other color",
    "Толщина линий и размер текста": "Line width and text size",
    "Отменить (⌘Z)": "Undo (⌘Z)",
    "Повторить (⇧⌘Z)": "Redo (⇧⌘Z)",
    "Скопировать изображение (⌘C)": "Copy image (⌘C)",
    "Сохранить как… (⌘S)": "Save As… (⌘S)",
    "Загрузка…": "Uploading…",
    "Загрузить": "Upload",
    "Загрузить на FTP/SFTP (⌘U)": "Upload via FTP/SFTP (⌘U)",
    "Shift — ровные линии и квадраты · Двойной клик — редактировать текст · ⌫ — удалить":
        "Shift — straight lines and squares · Double-click — edit text · ⌫ — delete",
    "Вписать": "Fit",
    "Скопировано в буфер обмена": "Copied to clipboard",
    "Сохранено: %@": "Saved: %@",
    "Укажите данные FTP или SFTP сервера в настройках.": "Enter your FTP or SFTP server details in Settings.",
    "Загружено на «%@». Ссылка скопирована: %@": "Uploaded to “%@”. Link copied: %@",
    "Загружено на «%@»: %@": "Uploaded to “%@”: %@",
    "Загружено на «%@»": "Uploaded to “%@”",

    // Recording
    "Отмена (Esc)": "Cancel (Esc)",
    "Записать весь экран": "Record the full screen",
    "Записать выделенную область": "Record a selected area",
    "Звук": "Audio",
    "Курсор": "Cursor",
    "Системный звук записывается": "System audio is recorded",
    "Системный звук не записывается": "System audio is not recorded",
    "Микрофон записывается": "Microphone is recorded",
    "Микрофон не записывается": "Microphone is not recorded",
    "Курсор виден на записи": "Cursor is visible",
    "Курсор скрыт на записи": "Cursor is hidden",
    "Записать": "Record",
    "Начать запись (↩)": "Start recording (↩)",
    "Сначала выделите область": "Select an area first",
    "Выделите мышью область для записи": "Drag to select the area to record",
    "Будет записан весь этот экран": "This entire screen will be recorded",
    "Щёлкните, чтобы записать этот экран": "Click to record this screen",
    "Пауза": "Pause",
    "Запись": "Recording",
    "Продолжить": "Resume",
    "Продолжить запись": "Resume recording",
    "Поставить на паузу": "Pause recording",
    "Завершить": "Stop",
    "Без системного звука": "No system audio",
    "Без микрофона": "No microphone",
    "Не удалось найти экран для записи": "Couldn't find the screen to record",
    "Запись пуста": "The recording is empty",
    "Клик — отмена": "Click to cancel",
    "Не удалось склеить запись": "Couldn't join the recording",
    "Запись — ": "Recording — ",
    "Сохранить": "Save",
    "Загружено на сервер": "Uploaded to server",
    "Показать в Finder": "Show in Finder",
    "Удалить запись и закрыть окно": "Delete the recording and close the window",
    "Загрузить на «%@»": "Upload to “%@”",
    "Сначала настройте сервер": "Set up a server first",
    "Выбрать, куда сохранить видео": "Choose where to save the video",
    "Сохранить в %@": "Save to %@",
]
