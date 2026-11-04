import Foundation

struct UploadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The active server's settings at this moment, so a retry picks up fixes made after a failure.
func currentServerConfig() throws -> ServerConfig {
    guard let config = ServerSettings.shared.activeConfig else {
        throw UploadError(message: L("Сервер не настроен"))
    }
    return config
}

struct UploadResult {
    /// Random name the file got on the server.
    let fileName: String
    let link: String?
}

enum Uploader {
    /// `progress` gets the transferred fraction (0...1) from a background thread once the file starts going out.
    /// Cancelling the calling task stops the transfer and throws `CancellationError`.
    static func upload(data: Data, fileExtension: String, config: ServerConfig,
                       progress: (@Sendable (Double) -> Void)? = nil) async throws -> UploadResult {
        let workDir = try makeWorkDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let file = workDir.appendingPathComponent(UUID().uuidString)
        try data.write(to: file)
        return try await upload(file: file, fileExtension: fileExtension, config: config, workDir: workDir, progress: progress)
    }

    static func upload(file: URL, config: ServerConfig, progress: (@Sendable (Double) -> Void)? = nil) async throws -> UploadResult {
        let workDir = try makeWorkDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        return try await upload(file: file, fileExtension: file.pathExtension, config: config, workDir: workDir, progress: progress)
    }

    private static func upload(file: URL, fileExtension: String, config: ServerConfig, workDir: URL,
                               progress: (@Sendable (Double) -> Void)?) async throws -> UploadResult {
        let existing = await remoteFileNames(config: config, workDir: workDir)
        try Task.checkCancellation()
        let fileName = randomName(fileExtension: fileExtension, existing: existing)
        let monitor = progress.map { ReadProgressMonitor(file: file, report: $0) }
        defer { monitor?.stop() }
        switch config.proto {
        case .ftp, .ftps:
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let timeout = max(180, size / 50_000)
            var args = ["--ftp-create-dirs", "-T", file.path]
            // "-" sends the command after the upload, "*" keeps a refused SITE CHMOD from failing it.
            if let mode = config.filePermissions { args += ["-Q", "-*SITE CHMOD \(mode) \(fileName)"] }
            let result = try await runCurl(config: config, extraArgs: args,
                                           url: ftpURL(config, fileName: fileName), timeout: timeout,
                                           onLaunch: monitor.map { m in { @Sendable pid in m.start(pid: pid) } })
            try checkCurl(result)
        case .sftp:
            var commands = mkdirCommands(for: config.remotePath)
            let remote = remoteFilePath(config.remotePath, fileName)
            commands.append("put \(quote(file.path)) \(quote(remote))")
            // A leading "-" lets the batch finish even if the server refuses chmod.
            if let mode = config.filePermissions { commands.append("-chmod \(mode) \(quote(remote))") }
            let result = try await runSFTP(config: config, commands: commands, workDir: workDir, onLaunch: monitor.map { m in { @Sendable pid in m.start(pid: pid) } })
            try checkSFTP(result)
        }
        return UploadResult(fileName: fileName, link: config.publicLink(for: fileName))
    }

    // MARK: Naming

    /// A 10-character id plus extension, e.g. `seCQ6wcUoL.png`, not yet present on the server.
    /// Latin letters and digits only, so the link works as-is in any browser and on any server.
    /// Collisions are checked case-insensitively, since some servers ignore case.
    static func randomName(fileExtension ext: String, existing: Set<String>) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        while true {
            let id = String((0..<10).map { _ in alphabet.randomElement()! })
            let candidate = id + (ext.isEmpty ? "" : ".\(ext.lowercased())")
            if !existing.contains(candidate.lowercased()) { return candidate }
        }
    }

    /// Lower-cased names in the upload folder. Best effort: an unreadable or missing folder counts as empty.
    private static func remoteFileNames(config c: ServerConfig, workDir: URL) async -> Set<String> {
        let output: String
        switch c.proto {
        case .ftp, .ftps:
            guard let result = try? await runCurl(config: c, extraArgs: ["--list-only"],
                                                  url: ftpURL(c, fileName: nil), timeout: 30),
                  result.status == 0 else { return [] }
            output = result.stdout
        case .sftp:
            let dir = c.remotePath.isEmpty ? "." : c.remotePath
            guard let result = try? await runSFTP(config: c, commands: ["-ls -1 \(quote(dir))"], workDir: workDir)
            else { return [] }
            output = result.stdout
        }
        var names = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) {
            let entry = line.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty, !entry.hasPrefix("sftp>") else { continue }
            names.insert((entry as NSString).lastPathComponent.lowercased())
        }
        return names
    }

    static func testConnection(config: ServerConfig) async throws {
        switch config.proto {
        case .ftp, .ftps:
            let result = try await runCurl(config: config, extraArgs: ["--list-only"],
                                           url: ftpURL(config, fileName: nil), timeout: 30)
            if result.status == 9 || result.status == 78 {
                throw UploadError(message: L("Вход выполнен, но папка «%@» не найдена. Она будет создана при первой загрузке.", config.remotePath))
            }
            try checkCurl(result)
        case .sftp:
            let workDir = try makeWorkDir()
            defer { try? FileManager.default.removeItem(at: workDir) }
            var commands = ["pwd"]
            if !config.remotePath.isEmpty { commands.append("-cd \(quote(config.remotePath))") }
            let result = try await runSFTP(config: config, commands: commands, workDir: workDir)
            try checkSFTP(result)
        }
    }

    // MARK: FTP / FTPS via curl

    private static func ftpURL(_ c: ServerConfig, fileName: String?) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/;?#")
        let host = c.host.contains(":") && !c.host.hasPrefix("[") ? "[\(c.host)]" : c.host
        let components = c.remotePath.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0)
        }
        var url = "ftp://\(host):\(c.port)/"
        if !components.isEmpty { url += components.joined(separator: "/") + "/" }
        if let fileName { url += fileName.addingPercentEncoding(withAllowedCharacters: allowed) ?? fileName }
        return url
    }

    private static func runCurl(config c: ServerConfig, extraArgs: [String], url: String, timeout: Int,
                                onLaunch: (@Sendable (pid_t) -> Void)? = nil) async throws -> ProcessResult {
        var args = ["-sS", "--connect-timeout", "15", "--max-time", String(timeout), "-K", "-"]
        if c.proto == .ftps { args.append("--ssl-reqd") }
        if c.proto == .ftps && c.allowInsecureTLS { args.append("-k") }
        if c.activeMode { args += ["--ftp-port", "-"] }
        args += extraArgs
        args.append(url)

        var curlConfig = ""
        if !c.username.isEmpty {
            curlConfig = "user = \"\(escapeCurl(c.username)):\(escapeCurl(c.password))\"\n"
        }
        return try await ProcessRunner.run("/usr/bin/curl", args, input: Data(curlConfig.utf8), onLaunch: onLaunch)
    }

    private static func escapeCurl(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func checkCurl(_ r: ProcessResult) throws {
        guard r.status != 0 else { return }
        let reason: String
        switch r.status {
        case 6: reason = L("Не удалось найти сервер (проверьте адрес)")
        case 7: reason = L("Не удалось подключиться к серверу (проверьте адрес и порт)")
        case 9: reason = L("Сервер отказал в доступе к папке")
        case 28: reason = L("Превышено время ожидания")
        case 35, 60: reason = L("Ошибка TLS/сертификата. Попробуйте включить «Не проверять сертификат»")
        case 64: reason = L("Сервер не поддерживает FTPS (TLS)")
        case 67: reason = L("Неверный логин или пароль")
        case 25: reason = L("Сервер не принял файл (нет прав на запись?)")
        default: reason = L("Ошибка curl %d", r.status)
        }
        let detail = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        throw UploadError(message: detail.isEmpty ? reason : "\(reason). \(detail)")
    }

    // MARK: SFTP via /usr/bin/sftp

    private static func runSFTP(config c: ServerConfig, commands: [String], workDir: URL,
                                onLaunch: (@Sendable (pid_t) -> Void)? = nil) async throws -> ProcessResult {
        let batch = workDir.appendingPathComponent("batch.txt")
        try (commands.joined(separator: "\n") + "\n").write(to: batch, atomically: true, encoding: .utf8)

        // BatchMode=no must precede -b, otherwise sftp forces BatchMode=yes and password auth is disabled.
        var args = [
            "-o", "BatchMode=no",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=15",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "ServerAliveInterval=10",
            "-P", String(c.port),
        ]
        if !c.keyPath.isEmpty { args += ["-i", c.keyPath] }
        args += ["-b", batch.path]
        args.append(c.username.isEmpty ? c.host : "\(c.username)@\(c.host)")

        var env = ProcessInfo.processInfo.environment
        if !c.password.isEmpty {
            let askpass = workDir.appendingPathComponent("askpass.sh")
            try "#!/bin/sh\nprintf '%s\\n' \"$SHOTTY_SFTP_SECRET\"\n".write(to: askpass, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)
            env["SSH_ASKPASS"] = askpass.path
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = env["DISPLAY"] ?? ":0"
            env["SHOTTY_SFTP_SECRET"] = c.password
        }
        return try await ProcessRunner.run("/usr/bin/sftp", args, environment: env, input: Data(), onLaunch: onLaunch)
    }

    private static func checkSFTP(_ r: ProcessResult) throws {
        guard r.status != 0 else { return }
        let err = r.stderr
        let reason: String
        if err.contains("Permission denied") {
            reason = L("Неверный логин, пароль или ключ")
        } else if err.contains("Could not resolve hostname") {
            reason = L("Не удалось найти сервер (проверьте адрес)")
        } else if err.contains("Connection refused") {
            reason = L("Сервер отклонил подключение (проверьте порт)")
        } else if err.contains("timed out") {
            reason = L("Превышено время ожидания")
        } else if err.contains("Host key verification failed") || err.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") {
            reason = L("Ключ сервера изменился. Проверьте ~/.ssh/known_hosts")
        } else if err.contains("No such file") {
            reason = L("Папка на сервере не найдена")
        } else {
            reason = L("Ошибка SFTP (код %d)", r.status)
        }
        let lastLines = err.split(separator: "\n").suffix(2).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        throw UploadError(message: lastLines.isEmpty ? reason : "\(reason). \(lastLines)")
    }

    private static func mkdirCommands(for path: String) -> [String] {
        let absolute = path.hasPrefix("/")
        var accumulated = absolute ? "" : nil as String?
        var commands: [String] = []
        for part in path.split(separator: "/") {
            if let current = accumulated {
                accumulated = current + "/" + part
            } else {
                accumulated = String(part)
            }
            commands.append("-mkdir \(quote(accumulated!))")
        }
        return commands
    }

    private static func remoteFilePath(_ dir: String, _ name: String) -> String {
        var d = dir
        while d.count > 1 && d.hasSuffix("/") { d.removeLast() }
        if d.isEmpty { return name }
        return d == "/" ? "/" + name : d + "/" + name
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func makeWorkDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotty-upload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return dir
    }
}

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunner {
    private final class Box: @unchecked Sendable { var data = Data() }

    /// Lets task cancellation terminate a process that may not have been launched yet.
    private final class Handle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        var isCancelled: Bool { lock.withLock { cancelled } }

        func attach(_ process: Process) {
            let cancelled = lock.withLock { self.process = process; return self.cancelled }
            if cancelled { process.terminate() }
        }

        func cancel() {
            let process = lock.withLock { cancelled = true; return self.process }
            if process?.isRunning == true { process?.terminate() }
        }
    }

    static func run(_ executable: String, _ args: [String], environment: [String: String]? = nil, input: Data?,
                    onLaunch: (@Sendable (pid_t) -> Void)? = nil) async throws -> ProcessResult {
        let handle = Handle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = args
                    if let environment { process.environment = environment }
                    let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe
                    process.standardInput = inPipe
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    handle.attach(process)
                    onLaunch?(process.processIdentifier)
                    if let input, !input.isEmpty { inPipe.fileHandleForWriting.write(input) }
                    try? inPipe.fileHandleForWriting.close()

                    let out = Box()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        out.data = outPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    process.waitUntilExit()
                    if handle.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    continuation.resume(returning: ProcessResult(
                        status: process.terminationStatus,
                        stdout: String(decoding: out.data, as: UTF8.self),
                        stderr: String(decoding: errData, as: UTF8.self)))
                }
            }
        } onCancel: {
            handle.cancel()
        }
    }
}

/// Reports upload progress by watching how far curl/sftp has read through the local file.
/// Neither tool prints usable progress when run without a terminal, but both read the file as they send it.
final class ReadProgressMonitor: @unchecked Sendable {
    private let inode: UInt64
    private let size: Int64
    private let report: @Sendable (Double) -> Void
    private let queue = DispatchQueue(label: "shotty.upload-progress")
    private var timer: DispatchSourceTimer?
    private var last = 0.0

    init(file: URL, report: @escaping @Sendable (Double) -> Void) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        inode = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        self.report = report
    }

    func start(pid: pid_t) {
        guard inode != 0, size > 0 else { return }
        queue.async {
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.poll(pid: pid) }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    private func poll(pid: pid_t) {
        guard let offset = Self.readOffset(pid: pid, inode: inode) else { return }
        // Capped below 1: the last bytes still have to reach the server after the file is read.
        let fraction = min(Double(offset) / Double(size), 0.99)
        guard fraction > last else { return }
        last = fraction
        report(fraction)
    }

    /// Current read position of `pid` in the file with this inode, or nil if it has no such file open.
    private static func readOffset(pid: pid_t, inode: UInt64) -> Int64? {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return nil }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufferSize) / MemoryLayout<proc_fdinfo>.stride)
        let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufferSize)
        guard used > 0 else { return nil }
        let infoSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        for fd in fds.prefix(Int(used) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, infoSize) == infoSize else { continue }
            if info.pvip.vip_vi.vi_stat.vst_ino == inode { return info.pfi.fi_offset }
        }
        return nil
    }
}
