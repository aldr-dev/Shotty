import AppKit
import SwiftUI
import Security
import UniformTypeIdentifiers

enum TransferProtocol: String, CaseIterable, Identifiable, Codable {
    case ftp = "FTP", ftps = "FTPS", sftp = "SFTP"
    var id: String { rawValue }
    var defaultPort: Int { self == .sftp ? 22 : 21 }
}

struct ServerConfig {
    var proto: TransferProtocol
    var host: String
    var port: Int
    var username: String
    var password: String
    var remotePath: String
    var publicURL: String
    var keyPath: String
    var activeMode: Bool
    var allowInsecureTLS: Bool
    /// Octal mode such as `0644` applied to the uploaded file; nil leaves the server's default.
    var filePermissions: String?

    func publicLink(for fileName: String) -> String? {
        let base = publicURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        return (base.hasSuffix("/") ? base : base + "/") + encoded
    }
}

struct ServerProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var proto: TransferProtocol = .sftp
    var host = ""
    var port = ""
    var username = ""
    var remotePath = ""
    var publicURL = ""
    var keyPath = ""
    var activeMode = false
    var allowInsecureTLS = false
    var filePermissions = ""

    var cleanHost: String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = h.range(of: "://") { h = String(h[range.upperBound...]) }
        while h.hasSuffix("/") { h.removeLast() }
        return h
    }

    var isConfigured: Bool { !cleanHost.isEmpty }

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        return cleanHost.isEmpty ? L("Новый сервер") : cleanHost
    }

    var summary: String {
        "\(proto.rawValue) · " + (cleanHost.isEmpty ? L("адрес не указан") : cleanHost)
            + (remotePath.isEmpty ? "" : " · \(remotePath)")
    }

    /// The permissions field as an octal mode (`644`, `0644`), or nil when empty or malformed.
    var validFilePermissions: String? {
        let mode = filePermissions.trimmingCharacters(in: .whitespaces)
        guard (3...4).contains(mode.count), mode.allSatisfy({ ("0"..."7").contains($0) }) else { return nil }
        return mode
    }
}

extension ServerProfile {
    // Profiles saved by older versions lack the newer keys; those keep their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        proto = try c.decodeIfPresent(TransferProtocol.self, forKey: .proto) ?? proto
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? host
        port = try c.decodeIfPresent(String.self, forKey: .port) ?? port
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? username
        remotePath = try c.decodeIfPresent(String.self, forKey: .remotePath) ?? remotePath
        publicURL = try c.decodeIfPresent(String.self, forKey: .publicURL) ?? publicURL
        keyPath = try c.decodeIfPresent(String.self, forKey: .keyPath) ?? keyPath
        activeMode = try c.decodeIfPresent(Bool.self, forKey: .activeMode) ?? activeMode
        allowInsecureTLS = try c.decodeIfPresent(Bool.self, forKey: .allowInsecureTLS) ?? allowInsecureTLS
        filePermissions = try c.decodeIfPresent(String.self, forKey: .filePermissions) ?? filePermissions
    }
}

final class ServerSettings: ObservableObject {
    static let shared = ServerSettings()
    private let defaults = UserDefaults.standard

    @Published var servers: [ServerProfile] { didSet { persistServers() } }
    @Published var activeID: UUID? { didSet { defaults.set(activeID?.uuidString, forKey: "activeServer") } }
    @Published private(set) var passwords: [UUID: String] = [:]
    @Published var copyLinkAfterUpload: Bool { didSet { defaults.set(copyLinkAfterUpload, forKey: "copyLink") } }

    private init() {
        Self.migrateFromLegacyDomain(into: defaults)
        copyLinkAfterUpload = defaults.object(forKey: "copyLink") as? Bool ?? true

        if let data = defaults.data(forKey: "servers"),
           let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            servers = decoded
        } else if let legacy = Self.legacyProfile(from: defaults) {
            servers = [legacy]
            let legacyPassword = Keychain.password(account: Keychain.legacyAccount)
            if !legacyPassword.isEmpty {
                Keychain.setPassword(legacyPassword, account: legacy.id.uuidString)
                Keychain.setPassword("", account: Keychain.legacyAccount)
            }
        } else {
            servers = [ServerProfile()]
        }
        persistServers()

        let stored = defaults.string(forKey: "activeServer").flatMap(UUID.init(uuidString:))
        activeID = servers.contains { $0.id == stored } ? stored : servers.first?.id
        for server in servers {
            passwords[server.id] = Keychain.password(account: server.id.uuidString)
        }
    }

    private func persistServers() {
        if let data = try? JSONEncoder().encode(servers) { defaults.set(data, forKey: "servers") }
    }

    private static func migrateFromLegacyDomain(into defaults: UserDefaults) {
        guard defaults.object(forKey: "servers") == nil, defaults.object(forKey: "proto") == nil,
              let legacy = UserDefaults(suiteName: "com.aldrmiller.screenshot") else { return }
        for key in ["proto", "host", "port", "username", "remotePath", "publicURL", "keyPath",
                    "activeMode", "allowInsecureTLS", "copyLink"] {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    private static func legacyProfile(from defaults: UserDefaults) -> ServerProfile? {
        guard let host = defaults.string(forKey: "host"), !host.isEmpty else { return nil }
        var p = ServerProfile()
        p.proto = TransferProtocol(rawValue: defaults.string(forKey: "proto") ?? "") ?? .sftp
        p.host = host
        p.port = defaults.string(forKey: "port") ?? ""
        p.username = defaults.string(forKey: "username") ?? ""
        p.remotePath = defaults.string(forKey: "remotePath") ?? ""
        p.publicURL = defaults.string(forKey: "publicURL") ?? ""
        p.keyPath = defaults.string(forKey: "keyPath") ?? ""
        p.activeMode = defaults.bool(forKey: "activeMode")
        p.allowInsecureTLS = defaults.bool(forKey: "allowInsecureTLS")
        return p
    }

    // MARK: Active server

    var active: ServerProfile? { servers.first { $0.id == activeID } ?? servers.first }

    var isConfigured: Bool { active?.isConfigured ?? false }

    var activeConfig: ServerConfig? {
        guard let active, active.isConfigured else { return nil }
        return config(for: active)
    }

    func config(for p: ServerProfile) -> ServerConfig {
        ServerConfig(
            proto: p.proto,
            host: p.cleanHost,
            port: Int(p.port.trimmingCharacters(in: .whitespaces)) ?? p.proto.defaultPort,
            username: p.username.trimmingCharacters(in: .whitespaces),
            password: password(for: p.id),
            remotePath: p.remotePath.trimmingCharacters(in: .whitespaces),
            publicURL: p.publicURL,
            keyPath: (p.keyPath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath,
            activeMode: p.activeMode,
            allowInsecureTLS: p.allowInsecureTLS,
            filePermissions: p.validFilePermissions)
    }

    /// Makes the next configured server active (wrapping around) and returns it.
    @discardableResult
    func selectNextServer() -> ServerProfile? {
        let candidates = servers.filter(\.isConfigured)
        guard !candidates.isEmpty else { return nil }
        let current = candidates.firstIndex { $0.id == activeID }
        let next = candidates[current.map { ($0 + 1) % candidates.count } ?? 0]
        activeID = next.id
        return next
    }

    // MARK: Editing

    func password(for id: UUID) -> String { passwords[id] ?? "" }

    func setPassword(_ value: String, for id: UUID) {
        passwords[id] = value
        Keychain.setPassword(value, account: id.uuidString)
    }

    func addServer() -> UUID {
        let profile = ServerProfile()
        servers.append(profile)
        if active?.isConfigured != true { activeID = profile.id }
        return profile.id
    }

    func removeServer(_ id: UUID) {
        servers.removeAll { $0.id == id }
        setPassword("", for: id)
        passwords[id] = nil
        if servers.isEmpty { servers = [ServerProfile()] }
        if !servers.contains(where: { $0.id == activeID }) {
            activeID = servers.first(where: \.isConfigured)?.id ?? servers.first?.id
        }
    }
}

enum Keychain {
    private static let service = "com.aldrmiller.screenshot.server"
    static let legacyAccount = "password"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func password(account: String) -> String {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func setPassword(_ value: String, account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var item = baseQuery(account)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrLabel as String] = L("Shotty — пароль сервера")
        SecItemAdd(item as CFDictionary, nil)
    }
}


// MARK: - Settings UI

struct ServerSettingsView: View {
    @ObservedObject var settings = ServerSettings.shared
    @State private var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSection(L("Серверы"), leading: 6, trailing: 6) {
                VStack(spacing: 4) {
                    ForEach(settings.servers) { server in
                        ServerRow(server: server,
                                  isActive: server.id == settings.active?.id,
                                  isSelected: server.id == selectedID,
                                  onSelect: { selectedID = server.id },
                                  onActivate: { settings.activeID = server.id; selectedID = server.id })
                    }
                    HStack(spacing: 6) {
                        GlassIconButton(symbol: "plus", help: L("Добавить сервер")) {
                            selectedID = settings.addServer()
                        }
                        GlassIconButton(symbol: "minus", help: L("Удалить выбранный сервер"), action: removeSelected)
                            .disabled(selectedID == nil || (settings.servers.count == 1 && settings.servers.first?.isConfigured == false))
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                }
                .padding(.vertical, 6)
            } footer: {
                Text(L("Отметьте кружком сервер, на который будут загружаться снимки. Переключать серверы можно горячей клавишей (см. «Основные») или из меню Shotty в строке меню."))
            }

            if let id = selectedID, let current = settings.servers.first(where: { $0.id == id }) {
                ServerEditor(profile: profileBinding(id, fallback: current),
                             password: Binding(get: { settings.password(for: id) },
                                               set: { settings.setPassword($0, for: id) }),
                             copyLink: $settings.copyLinkAfterUpload)
                    .id(id)
            }
        }
        .onAppear { if selectedID == nil { selectedID = settings.active?.id } }
        // Switching the upload server anywhere (hotkey, menu) also highlights it here.
        .onChange(of: settings.active?.id) { _, id in if let id { selectedID = id } }
    }

    private func removeSelected() {
        guard let id = selectedID else { return }
        let ids = settings.servers.map(\.id)
        let index = ids.firstIndex(of: id) ?? 0
        let remaining = ids.filter { $0 != id }
        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
        settings.removeServer(id)
        if selectedID == nil { selectedID = settings.servers.first?.id }
    }

    private func profileBinding(_ id: UUID, fallback: ServerProfile) -> Binding<ServerProfile> {
        Binding(
            get: { settings.servers.first { $0.id == id } ?? fallback },
            set: { newValue in
                if let i = settings.servers.firstIndex(where: { $0.id == id }) { settings.servers[i] = newValue }
            })
    }
}

private struct ServerRow: View {
    let server: ServerProfile
    let isActive: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 12) {
            Button(action: onActivate) { radio }
                .buttonStyle(.hand(.plain))
                .help(isActive ? L("Сюда загружаются снимки") : L("Загружать снимки на этот сервер"))
                .disabled(!server.isConfigured)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsStyle.primary(scheme))
                Text(server.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? (dark ? Glass.hex(0xC4CBE0) : Glass.hex(0x2C3346)) : SettingsStyle.secondary(scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if isActive {
                Text(L("для загрузки"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(dark ? Glass.hex(0xCFE0FF) : .white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(dark ? Glass.hex(0x3A6BFF, 0.3) : Glass.hex(0x1F4F9A)))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            if isSelected {
                shape.fill(dark ? Glass.hex(0x3A6BFF, 0.16) : Glass.hex(0x1F4F9A, 0.1))
                    .overlay(shape.strokeBorder(dark ? Glass.hex(0x5B8CFF, 0.45) : Glass.hex(0x1F4F9A, 0.25), lineWidth: 0.5))
            } else if hovering {
                shape.fill(dark ? Color.white.opacity(0.06) : Color.white.opacity(0.5))
            }
        }
        .contentShape(Rectangle())
        // The whole row picks the upload server, like the radio button; one that isn't set up yet
        // can only be opened for editing.
        .onTapGesture { server.isConfigured ? onActivate() : onSelect() }
        .onHover { hovering = $0 }
        .handCursor()
    }

    private var radio: some View {
        let dark = scheme == .dark
        return ZStack {
            if isActive {
                Circle().fill(SettingsStyle.accent(scheme))
                    .shadow(color: dark ? Glass.hex(0x3A6BFF, 0.6) : Glass.hex(0x1F4F9A, 0.35),
                            radius: dark ? 5 : 3, y: dark ? 0 : 2)
                Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white)
            } else {
                Circle().fill(dark ? Color.clear : Color.white.opacity(0.6))
                Circle().strokeBorder(dark ? Color.white.opacity(0.35) : Glass.hex(0x102A54, 0.35), lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
        .contentShape(Circle())
    }
}

private struct ServerEditor: View {
    @Binding var profile: ServerProfile
    @Binding var password: String
    @Binding var copyLink: Bool
    @State private var testing = false
    @State private var testResult: (ok: Bool, message: String)?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GlassSection(L("Подключение"), detail: profile.displayName) {
            GlassRow(title: L("Название")) {
                GlassField(placeholder: L("например, Рабочий"), text: $profile.name)
            }
            GlassRow(title: L("Протокол")) {
                GlassSegmented(options: TransferProtocol.allCases, selection: $profile.proto,
                               title: \.rawValue, itemWidth: 70)
            }
            GlassRow(title: L("Сервер")) {
                GlassField(placeholder: "ftp.example.com", text: $profile.host)
            }
            GlassRow(title: L("Порт")) {
                GlassField(placeholder: "\(profile.proto.defaultPort)", text: $profile.port, width: 90)
            }
            GlassRow(title: L("Пользователь")) {
                GlassField(placeholder: profile.proto == .sftp ? "user" : "anonymous", text: $profile.username)
            }
            GlassRow(title: L("Пароль")) {
                GlassField(placeholder: L("хранится в Связке ключей"), text: $password, secure: true)
            }
            if profile.proto == .sftp {
                GlassRow(title: L("SSH-ключ"), showsDivider: false) {
                    HStack(spacing: 8) {
                        GlassField(placeholder: L("необязательно, ~/.ssh/id_ed25519"), text: $profile.keyPath, width: 150)
                        GlassButton(title: L("Выбрать…"), action: chooseKey)
                    }
                }
            } else {
                GlassRow(title: L("Активный режим"), detail: "PORT", showsDivider: profile.proto == .ftps) {
                    GlassSwitch(isOn: $profile.activeMode)
                }
            }
            if profile.proto == .ftps {
                GlassRow(title: L("Не проверять сертификат сервера"), showsDivider: false) {
                    GlassSwitch(isOn: $profile.allowInsecureTLS)
                }
            }
        } footer: {
            Text(protocolHint)
        }

        GlassSection(L("Размещение файлов"), footerLineHeight: 1.6) {
            GlassRow(symbol: "folder", tint: .purple, title: L("Папка на сервере")) {
                GlassField(placeholder: "uploads/screens", text: $profile.remotePath, width: 220)
            }
            GlassRow(symbol: "link", tint: .blue, title: L("Публичный URL папки")) {
                GlassField(placeholder: "https://example.com/screens", text: $profile.publicURL, width: 220)
            }
            GlassRow(symbol: "lock", tint: .orange, title: L("Права файла"), showsDivider: false) {
                GlassField(placeholder: "0644", text: $profile.filePermissions, width: 90)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 11 * 1.6 - 13.1) {
                Text(L("Если папки нет — она будет создана."))
                Text(L("Публичный URL нужен, чтобы после загрузки получить готовую ссылку на картинку."))
                if hasInvalidPermissions {
                    Text(L("Права указываются восьмеричным числом, например 0644 или 644. Сейчас они не применяются."))
                        .foregroundStyle(.red)
                } else {
                    Text(L("Права выставляются файлу после загрузки. Если поле пустое, их задаёт сервер."))
                }
            }
        }

        GlassSection(trailing: 10) {
            GlassRow(symbol: "waveform.path.ecg", tint: .green, title: L("Подключение"), height: 48) {
                HStack(spacing: 12) {
                    if testing {
                        ProgressView().controlSize(.small)
                    } else if let testResult {
                        Text(testResult.ok ? L("успешно") : L("ошибка"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(testResult.ok ? Color.green : .red)
                    }
                    GlassPrimaryButton(title: L("Проверить"), action: runTest)
                        .disabled(testing || !profile.isConfigured)
                }
            }
            if let result = testResult, !result.ok {
                Text(result.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(SettingsStyle.divider(scheme)).frame(height: 0.5)
                    }
            }
            GlassRow(symbol: "doc.on.doc", tint: .blue, title: L("Копировать ссылку после загрузки"), showsDivider: false) {
                GlassSwitch(isOn: $copyLink).padding(.trailing, 4)
            }
        }
        .padding(.top, 6)
        .onChange(of: profile.proto) { _, _ in testResult = nil }
    }

    private var hasInvalidPermissions: Bool {
        !profile.filePermissions.trimmingCharacters(in: .whitespaces).isEmpty && profile.validFilePermissions == nil
    }

    private var protocolHint: String {
        switch profile.proto {
        case .ftp: L("Обычный FTP без шифрования. Путь указывается относительно домашней папки пользователя.")
        case .ftps: L("FTP с шифрованием TLS (explicit, AUTH TLS). Путь указывается относительно домашней папки пользователя.")
        case .sftp: L("Передача файлов по SSH. Можно войти по паролю или по SSH-ключу. Путь, начинающийся с «/», считается абсолютным.")
        }
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            profile.keyPath = url.path
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        let config = ServerSettings.shared.config(for: profile)
        Task { @MainActor in
            do {
                try await Uploader.testConnection(config: config)
                testResult = (true, L("Подключение успешно"))
            } catch {
                testResult = (false, error.localizedDescription)
            }
            testing = false
        }
    }
}

enum SettingsTab: Hashable {
    case general, server
}

final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var tab: SettingsTab = .general
}

struct SettingsRootView: View {
    @ObservedObject private var navigation = SettingsNavigation.shared
    @Environment(\.colorScheme) private var scheme

    /// Matches the home window's scale: same width, controls at the same sizes.
    static let width: CGFloat = 560
    static let height: CGFloat = 720
    /// Height of the title bar with its empty toolbar; the traffic lights sit on its middle line.
    static let titleBarHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 12) {
            Text(L("Настройки Shotty"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SettingsStyle.title(scheme))
                .frame(height: Self.titleBarHeight)
                .padding(.bottom, -12)
                .allowsHitTesting(false)
            // A custom segmented control instead of TabView: the native tabs can't show the pointing-hand cursor.
            GlassSegmented(options: [SettingsTab.general, .server], selection: $navigation.tab,
                           title: { $0 == .general ? L("Основные") : L("Серверы") }, kind: .tabs)
            ScrollView {
                Group {
                    switch navigation.tab {
                    case .general: GeneralSettingsView()
                    case .server: ServerSettingsView()
                    }
                }
                // The first caption is 6 pt below the tabs, not 8.
                .padding(.top, -2)
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: Self.width, height: Self.height)
        .background(Glass.background(scheme))
        // The content runs under the transparent title bar; the title row above leaves room for it.
        .ignoresSafeArea()
    }
}
