import AppKit
import AVFoundation
import ScreenCaptureKit

enum RecordingArea: String {
    case fullScreen, area
}

final class RecordingSettings: ObservableObject {
    static let shared = RecordingSettings()
    private let defaults = UserDefaults.standard

    @Published var recordSystemAudio: Bool { didSet { defaults.set(recordSystemAudio, forKey: "rec.systemAudio") } }
    @Published var recordMicrophone: Bool { didSet { defaults.set(recordMicrophone, forKey: "rec.microphone") } }
    @Published var showCursor: Bool { didSet { defaults.set(showCursor, forKey: "rec.cursor") } }
    @Published var area: RecordingArea { didSet { defaults.set(area.rawValue, forKey: "rec.area") } }
    @Published var folderPath: String { didSet { defaults.set(folderPath, forKey: "rec.folder") } }

    private init() {
        recordSystemAudio = defaults.object(forKey: "rec.systemAudio") as? Bool ?? true
        recordMicrophone = defaults.object(forKey: "rec.microphone") as? Bool ?? false
        showCursor = defaults.object(forKey: "rec.cursor") as? Bool ?? true
        area = RecordingArea(rawValue: defaults.string(forKey: "rec.area") ?? "") ?? .area
        folderPath = defaults.string(forKey: "rec.folder")
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Shotty").path
    }

    var folderURL: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }
    var folderDisplay: String { (folderPath as NSString).abbreviatingWithTildeInPath }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = folderURL
        panel.prompt = L("Выбрать")
        if panel.runModal() == .OK, let url = panel.url { folderPath = url.path }
    }
}

struct RecordingOptions {
    var selection: RegionSelection
    var systemAudio: Bool
    var microphone: Bool
    var showCursor: Bool
}

/// Records the screen in segments (so it can pause) and joins them into one file when stopped.
@MainActor
final class ScreenRecorder: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput, SCRecordingOutputDelegate {
    static let shared = ScreenRecorder()

    enum State: Equatable { case idle, recording, paused, finishing }

    @Published private(set) var state: State = .idle { didSet { onStateChange?(state) } }
    @Published private(set) var elapsed: TimeInterval = 0
    private(set) var options: RecordingOptions?
    var onStateChange: ((State) -> Void)?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var segmentURL: URL?
    private var segments: [URL] = []
    private var workDir: URL?
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var ticker: Timer?
    private var segmentFinished: CheckedContinuation<Void, Never>?
    private var busy = false
    private var completion: ((Result<URL, Error>) -> Void)?
    private let sampleQueue = DispatchQueue(label: "shotty.recorder.samples")

    var isActive: Bool { state != .idle }

    /// `completion` fires once with the joined file (in a temporary folder) or an error.
    func start(_ options: RecordingOptions, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        guard state == .idle else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotty-rec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.options = options
        workDir = dir
        segments = []
        accumulated = 0
        elapsed = 0
        do {
            try await startSegment()
        } catch {
            try? FileManager.default.removeItem(at: dir)
            reset()
            throw error
        }
        self.completion = completion
        state = .recording
        startTicker()
    }

    func pause() {
        guard state == .recording, !busy else { return }
        busy = true
        state = .paused
        Task {
            await endSegment()
            busy = false
        }
    }

    func resume() {
        guard state == .paused, !busy else { return }
        busy = true
        Task {
            do {
                try await startSegment()
                busy = false
                state = .recording
            } catch {
                busy = false
                HUD.show(L("Не удалось продолжить запись: %@", error.localizedDescription), isError: true)
                await finish(error: nil)
            }
        }
    }

    func togglePause() { state == .paused ? resume() : pause() }

    func stop() {
        guard state == .recording || state == .paused else { return }
        Task { await finish(error: nil) }
    }

    // MARK: Segments

    private func startSegment() async throws {
        guard let options, let workDir else { return }
        let selection = options.selection
        let displayID = selection.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw UploadError(message: L("Не удалось найти экран для записи"))
        }
        let ownApps = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let screenSize = selection.screen.frame.size
        let source = selection.rect.map {
            CGRect(x: $0.minX, y: screenSize.height - $0.maxY, width: $0.width, height: $0.height)
        } ?? CGRect(origin: .zero, size: screenSize)
        let scale = CGFloat(filter.pointPixelScale)

        let config = SCStreamConfiguration()
        if selection.rect != nil { config.sourceRect = source }
        config.width = Self.even(source.width * scale)
        config.height = Self.even(source.height * scale)
        // 30 fps is plenty for screen content and keeps files noticeably smaller than 60.
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 6
        config.showsCursor = options.showCursor
        config.capturesAudio = options.systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.captureMicrophone = options.microphone
        if options.microphone, let mic = AVCaptureDevice.default(for: .audio) {
            config.microphoneCaptureDeviceID = mic.uniqueID
        }

        let url = workDir.appendingPathComponent("segment-\(segments.count).mp4")
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = url
        recordingConfig.outputFileType = .mp4
        recordingConfig.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        // Without registered sample outputs ScreenCaptureKit may skip delivering that media to the recording.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if options.systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue) }
        if options.microphone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue) }
        try stream.addRecordingOutput(output)

        self.stream = stream
        recordingOutput = output
        segmentURL = url
        try await stream.startCapture()
        segmentStart = Date()
    }

    private func endSegment() async {
        guard let stream else { return }
        if let start = segmentStart { accumulated += Date().timeIntervalSince(start) }
        segmentStart = nil
        await withCheckedContinuation { continuation in
            segmentFinished = continuation
            Task { try? await stream.stopCapture() }
            // Fallback in case the recording delegate never reports completion.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.segmentDidEnd() }
        }
        if let url = segmentURL, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
            segments.append(url)
        }
        self.stream = nil
        recordingOutput = nil
        segmentURL = nil
    }

    private func segmentDidEnd() {
        let continuation = segmentFinished
        segmentFinished = nil
        continuation?.resume()
    }

    private func finish(error: Error?) async {
        guard state != .finishing && state != .idle else { return }
        state = .finishing
        stopTicker()
        while busy { try? await Task.sleep(for: .milliseconds(50)) }
        await endSegment()
        let completion = self.completion
        let segments = self.segments
        let workDir = self.workDir
        reset()

        if let error {
            if let workDir { try? FileManager.default.removeItem(at: workDir) }
            completion?(.failure(error))
            return
        }
        guard !segments.isEmpty, let workDir else {
            if let workDir { try? FileManager.default.removeItem(at: workDir) }
            completion?(.failure(UploadError(message: L("Запись пуста"))))
            return
        }
        do {
            let output = workDir.appendingPathComponent(Self.fileName())
            try await Self.join(segments, to: output)
            for segment in segments where segment != output { try? FileManager.default.removeItem(at: segment) }
            completion?(.success(output))
        } catch {
            completion?(.failure(error))
        }
    }

    private func reset() {
        stopTicker()
        stream = nil
        recordingOutput = nil
        segmentURL = nil
        segments = []
        workDir = nil
        completion = nil
        options = nil
        segmentStart = nil
        state = .idle
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        elapsed = accumulated + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Joining

    private static func join(_ segments: [URL], to output: URL) async throws {
        if segments.count == 1 {
            try FileManager.default.moveItem(at: segments[0], to: output)
            return
        }
        let composition = AVMutableComposition()
        var compositionTracks: [String: AVMutableCompositionTrack] = [:]
        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            var perType: [AVMediaType: Int] = [:]
            for track in try await asset.load(.tracks) {
                let type = track.mediaType
                let index = perType[type, default: 0]
                perType[type] = index + 1
                let key = "\(type.rawValue)-\(index)"
                guard let target = compositionTracks[key]
                        ?? composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)
                else { continue }
                compositionTracks[key] = target
                let range = try await track.load(.timeRange)
                try target.insertTimeRange(range, of: track, at: cursor + range.start)
            }
            cursor = cursor + duration
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw UploadError(message: L("Не удалось склеить запись"))
        }
        try await export.export(to: output, as: .mp4)
    }

    static func fileName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "shotty_" + f.string(from: date) + ".mp4"
    }

    private static func even(_ value: CGFloat) -> Int { max(2, Int(value.rounded()) & ~1) }

    // MARK: Delegates

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            // Stopped from outside (e.g. the system menu bar indicator): keep what was recorded.
            if self.segmentFinished != nil { self.segmentDidEnd() } else { await self.finish(error: nil) }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            if self.recordingOutput === recordingOutput { self.segmentDidEnd() }
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.recordingOutput === recordingOutput else { return }
            if self.segmentFinished != nil {
                self.segmentDidEnd()
            } else {
                await self.finish(error: error)
            }
        }
    }
}
