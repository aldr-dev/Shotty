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
            allowInsecureTLS: p.allowInsecureTLS)
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
        Form {
            Section {
                ForEach(settings.servers) { server in
                    ServerRow(server: server,
                              isActive: server.id == settings.active?.id,
                              isSelected: server.id == selectedID,
                              onSelect: { selectedID = server.id },
                              onActivate: { settings.activeID = server.id; selectedID = server.id })
                }
                HStack(spacing: 6) {
                    Button {
                        selectedID = settings.addServer()
                    } label: {
                        Image(systemName: "plus").frame(width: 14, height: 14)
                    }
                    .help(L("Добавить сервер"))
                    Button {
                        guard let id = selectedID else { return }
                        let ids = settings.servers.map(\.id)
                        let index = ids.firstIndex(of: id) ?? 0
                        let remaining = ids.filter { $0 != id }
                        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
                        settings.removeServer(id)
                        if selectedID == nil { selectedID = settings.servers.first?.id }
                    } label: {
                        Image(systemName: "minus").frame(width: 14, height: 14)
                    }
                    .help(L("Удалить выбранный сервер"))
                    .disabled(selectedID == nil || (settings.servers.count == 1 && settings.servers.first?.isConfigured == false))
                    Spacer()
                }
            } header: {
                Label(L("Серверы"), systemImage: "server.rack")
            } footer: {
                Text(L("Отметьте кружком сервер, на который будут загружаться снимки. Переключать серверы можно горячей клавишей (см. «Основные») или из меню Shotty в строке меню."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let id = selectedID, let current = settings.servers.first(where: { $0.id == id }) {
                ServerEditor(profile: profileBinding(id, fallback: current),
                             password: Binding(get: { settings.password(for: id) },
                                               set: { settings.setPassword($0, for: id) }))
                    .id(id)
            }

            Section {
                Toggle(L("Копировать ссылку после загрузки"), isOn: $settings.copyLinkAfterUpload)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520)
        .onAppear { if selectedID == nil { selectedID = settings.active?.id } }
        // Switching the upload server anywhere (hotkey, menu) also highlights it here.
        .onChange(of: settings.active?.id) { _, id in if let id { selectedID = id } }
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

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onActivate) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.hand(.plain))
            .help(isActive ? L("Сюда загружаются снимки") : L("Загружать снимки на этот сервер"))
            .disabled(!server.isConfigured)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName).font(.system(size: 13, weight: .semibold))
                Text(server.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isActive {
                Text(L("для загрузки"))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear))
        .contentShape(Rectangle())
        // The whole row picks the upload server, like the radio button; one that isn't set up yet
        // can only be opened for editing.
        .onTapGesture { server.isConfigured ? onActivate() : onSelect() }
        .handCursor()
    }
}

private struct ServerEditor: View {
    @Binding var profile: ServerProfile
    @Binding var password: String
    @State private var testing = false
    @State private var testResult: (ok: Bool, message: String)?

    var body: some View {
        Section {
            TextField(L("Название"), text: $profile.name, prompt: Text(L("например, Рабочий")))
            Picker(L("Протокол"), selection: $profile.proto) {
                ForEach(TransferProtocol.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .handCursor()

            TextField(L("Сервер"), text: $profile.host, prompt: Text("ftp.example.com"))
            TextField(L("Порт"), text: $profile.port, prompt: Text("\(profile.proto.defaultPort)"))
            TextField(L("Пользователь"), text: $profile.username, prompt: Text(profile.proto == .sftp ? "user" : "anonymous"))
            SecureField(L("Пароль"), text: $password, prompt: Text(L("хранится в Связке ключей")))

            if profile.proto == .sftp {
                HStack {
                    TextField(L("SSH-ключ"), text: $profile.keyPath, prompt: Text(L("необязательно, ~/.ssh/id_ed25519")))
                    Button(L("Выбрать…"), action: chooseKey)
                }
            } else {
                Toggle(L("Активный режим (PORT)"), isOn: $profile.activeMode)
            }
            if profile.proto == .ftps {
                Toggle(L("Не проверять сертификат сервера"), isOn: $profile.allowInsecureTLS)
            }
        } header: {
            Label(L("Подключение — %@", profile.displayName), systemImage: "network")
        } footer: {
            Text(protocolHint).font(.caption).foregroundStyle(.secondary)
        }

        Section {
            TextField(L("Папка на сервере"), text: $profile.remotePath, prompt: Text("uploads/screens"))
            TextField(L("Публичный URL папки"), text: $profile.publicURL, prompt: Text("https://example.com/screens"))
        } header: {
            Label(L("Размещение файлов"), systemImage: "folder")
        } footer: {
            Text(L("Если папки нет — она будет создана. Публичный URL нужен, чтобы после загрузки получить готовую ссылку на картинку."))
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            HStack(spacing: 12) {
                Button {
                    runTest()
                } label: {
                    Label(L("Проверить подключение"), systemImage: "bolt.horizontal.circle")
                }
                .disabled(testing || !profile.isConfigured)

                if testing {
                    ProgressView().controlSize(.small)
                } else if let result = testResult {
                    Label(result.message, systemImage: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(result.ok ? .green : .red)
                        .font(.callout)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
        }
        .onChange(of: profile.proto) { _, _ in testResult = nil }
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

    var body: some View {
        // A segmented control instead of TabView: the native tabs can't show the pointing-hand cursor.
        VStack(spacing: 0) {
            Picker("", selection: $navigation.tab) {
                Label(L("Основные"), systemImage: "keyboard").tag(SettingsTab.general)
                Label(L("Серверы"), systemImage: "server.rack").tag(SettingsTab.server)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .handCursor()
            .padding(.vertical, 10)
            Divider()
            Group {
                switch navigation.tab {
                case .general: GeneralSettingsView()
                case .server: ServerSettingsView()
                }
            }
            // Same background as the tab bar above, so the window reads as one surface.
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 580, height: 720)
    }
}
