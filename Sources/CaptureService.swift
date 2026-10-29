import AppKit

enum CaptureMode {
    case area, window, fullScreen
}

enum CaptureService {
    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    static func capture(_ mode: CaptureMode, completion: @escaping (NSImage?) -> Void) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotty-\(UUID().uuidString).png")
        var args: [String]
        switch mode {
        case .area: args = ["-i", "-s"]
        case .window: args = ["-i", "-w"]
        case .fullScreen: args = ["-m"]
        }
        args.append(url.path)

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = args
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let data = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async {
                completion(data.flatMap { NSImage(data: $0) })
            }
        }
    }
}
