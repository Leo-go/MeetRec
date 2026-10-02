import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

private let sampleRate: Double = 48_000
private let channels: AVAudioChannelCount = 2

private enum CaptureMode: String {
    case microphone
    case system
    case both

    var title: String {
        switch self {
        case .microphone: return "Только микрофон"
        case .system: return "Только звук компьютера"
        case .both: return "Микрофон и встреча"
        }
    }
}

private enum RecorderError: LocalizedError {
    case noDisplay
    case permission(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "Не вижу экран, с которого можно снять звук."
        case .permission(let message):
            return message
        }
    }
}

private let appDelegate = AppDelegate()

@main
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = appDelegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recorder = Recorder()
    private var mode: CaptureMode = .both
    private var window: NSWindow!
    private var statusLabel: NSTextField!
    private var modePopup: NSPopUpButton!
    private var recordButton: NSButton!
    private var startItem: NSMenuItem!
    private var modeMenuItems: [CaptureMode: NSMenuItem] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let saved = UserDefaults.standard.string(forKey: "mode"),
           let parsed = CaptureMode(rawValue: saved) {
            mode = parsed
        }
        buildMenus()
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder.isRecording else { return .terminateNow }
        recorder.stop { _ in
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    private func buildMenus() {
        let main = NSMenu()

        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let about = NSMenuItem(title: "О программе", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        main.addItem(appItem)

        let fileMenu = NSMenu(title: "Файл")
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        startItem = NSMenuItem(title: "Начать запись", action: #selector(toggleRecording), keyEquivalent: "r")
        startItem.target = self
        fileMenu.addItem(startItem)
        fileMenu.addItem(.separator())
        let folder = NSMenuItem(title: "Открыть папку записей", action: #selector(openFolder), keyEquivalent: "o")
        folder.target = self
        fileMenu.addItem(folder)
        main.addItem(fileItem)

        let settingsMenu = NSMenu(title: "Настройки")
        let settingsItem = NSMenuItem()
        settingsItem.submenu = settingsMenu
        for item in [CaptureMode.both, .system, .microphone] {
            let entry = NSMenuItem(title: item.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.rawValue
            settingsMenu.addItem(entry)
            modeMenuItems[item] = entry
        }
        main.addItem(settingsItem)

        NSApp.mainMenu = main
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 230),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Запись встречи"
        window.isReleasedWhenClosed = false

        let content = NSView()
        window.contentView = content

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString: "Микрофон и звук встречи пишутся в один WAV. Картинка не сохраняется. То же самое есть в меню «Файл» и «Настройки» сверху.")
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let modeLabel = NSTextField(labelWithString: "Что писать")
        modeLabel.translatesAutoresizingMaskIntoConstraints = false

        modePopup = NSPopUpButton()
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        modePopup.target = self
        modePopup.action = #selector(selectModeFromPopup(_:))
        for item in [CaptureMode.both, .system, .microphone] {
            modePopup.addItem(withTitle: item.title)
            modePopup.lastItem?.representedObject = item.rawValue
        }

        recordButton = NSButton(title: "Начать запись", target: self, action: #selector(toggleRecording))
        recordButton.bezelStyle = .rounded
        recordButton.controlSize = .large
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.keyEquivalent = "\r"

        let folderButton = NSButton(title: "Папка записей", target: self, action: #selector(openFolder))
        folderButton.bezelStyle = .rounded
        folderButton.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(statusLabel)
        content.addSubview(hint)
        content.addSubview(modeLabel)
        content.addSubview(modePopup)
        content.addSubview(recordButton)
        content.addSubview(folderButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            hint.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            hint.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),

            modeLabel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 20),
            modeLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),

            modePopup.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            modePopup.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 12),

            recordButton.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 24),
            recordButton.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            recordButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),

            folderButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            folderButton.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: 12)
        ])

        refreshUI()
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private func refreshUI() {
        let recording = recorder.isRecording
        statusLabel.stringValue = recording ? "Идёт запись" : "Готов к записи"
        statusLabel.textColor = recording ? .systemRed : .labelColor
        recordButton.title = recording ? "Остановить и сохранить" : "Начать запись"
        startItem.title = recordButton.title
        modePopup.isEnabled = !recording
        window.title = recording ? "Идёт запись" : "Запись встречи"
        for (item, menuItem) in modeMenuItems {
            menuItem.state = item == mode ? .on : .off
            menuItem.isEnabled = !recording
        }
        if let index = modePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == mode.rawValue }) {
            modePopup.selectItem(at: index)
        }
    }

    @objc private func toggleRecording() {
        recordButton.isEnabled = false
        startItem.isEnabled = false
        if recorder.isRecording {
            recorder.stop { [weak self] result in
                DispatchQueue.main.async {
                    self?.recordButton.isEnabled = true
                    self?.startItem.isEnabled = true
                    self?.refreshUI()
                    switch result {
                    case .success(let url):
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    case .failure(let error):
                        self?.alert(error.localizedDescription)
                    }
                }
            }
            statusLabel.stringValue = "Сохраняю…"
            return
        }

        statusLabel.stringValue = "Запускаю…"
        recorder.start(mode: mode) { [weak self] error in
            DispatchQueue.main.async {
                self?.recordButton.isEnabled = true
                self?.startItem.isEnabled = true
                if let error {
                    self?.alert(error.localizedDescription)
                }
                self?.refreshUI()
            }
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let next = CaptureMode(rawValue: raw) else { return }
        applyMode(next)
    }

    @objc private func selectModeFromPopup(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let next = CaptureMode(rawValue: raw) else { return }
        applyMode(next)
    }

    private func applyMode(_ next: CaptureMode) {
        mode = next
        UserDefaults.standard.set(next.rawValue, forKey: "mode")
        refreshUI()
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(Recorder.folder)
    }

    @objc private func showAbout() {
        alert("Пишет микрофон и звук компьютера в один файл WAV, без видео. Файлы лежат в папке Recordings/MeetRec в домашней папке.")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func alert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Запись встречи"
        alert.informativeText = text
        alert.runModal()
    }
}

private final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    static var folder: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings/MeetRec", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private(set) var isRecording = false
    private let lock = NSLock()
    private var mode: CaptureMode = .both
    private var stream: SCStream?
    private var engine: AVAudioEngine?
    private var micConverter: AVAudioConverter?
    private var micFile: AVAudioFile?
    private var systemFile: AVAudioFile?
    private var sessionFolder: URL?
    private var startedAt = Date()
    private let audioQueue = DispatchQueue(label: "local.leogo.MeetRec.audio")
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: channels,
        interleaved: false
    )!

    func start(mode: CaptureMode, completion: @escaping (Error?) -> Void) {
        lock.lock()
        if isRecording {
            lock.unlock()
            completion(nil)
            return
        }
        self.mode = mode
        startedAt = Date()
        let folder = Self.folder.appendingPathComponent(fileStamp(startedAt), isDirectory: true)
        sessionFolder = folder
        lock.unlock()

        Task {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if mode != .system {
                    try startMicrophone(in: folder)
                }
                if mode != .microphone {
                    try await startSystemAudio(in: folder)
                }
                self.lock.lock()
                self.isRecording = true
                self.lock.unlock()
                completion(nil)
            } catch {
                self.teardown()
                completion(error)
            }
        }
    }

    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        lock.lock()
        let folder = sessionFolder
        let mode = self.mode
        let started = startedAt
        isRecording = false
        lock.unlock()

        Task {
            await stopSystemAudio()
            stopMicrophone()
            do {
                guard let folder else { throw RecorderError.permission("Папка записи пропала.") }
                let output = Self.folder.appendingPathComponent("встреча-\(fileStamp(started)).wav")
                try mix(mode: mode, folder: folder, to: output)
                try? FileManager.default.removeItem(at: folder)
                completion(.success(output))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func startMicrophone(in folder: URL) throws {
        let session = AVCaptureDevice.authorizationStatus(for: .audio)
        if session == .notDetermined {
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { _ in semaphore.signal() }
            semaphore.wait()
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.permission("Нет доступа к микрофону. Системные настройки → Конфиденциальность → Микрофон → MeetRec.")
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else {
            throw RecorderError.permission("Микрофон не отдаёт звук. Проверь, что он выбран в настройках звука.")
        }
        guard let converter = AVAudioConverter(from: hardware, to: targetFormat) else {
            throw RecorderError.permission("Не получилось подготовить микрофон к записи.")
        }
        let file = try AVAudioFile(forWriting: folder.appendingPathComponent("mic.caf"), settings: targetFormat.settings)
        input.installTap(onBus: 0, bufferSize: 4096, format: hardware) { [weak self] buffer, _ in
            self?.writeMicrophone(buffer)
        }
        engine.prepare()
        try engine.start()
        lock.lock()
        self.engine = engine
        self.micConverter = converter
        self.micFile = file
        lock.unlock()
    }

    private func writeMicrophone(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let converter = micConverter
        let file = micFile
        lock.unlock()
        guard let converter, let file, let converted = convert(buffer, with: converter) else { return }
        lock.lock()
        defer { lock.unlock() }
        try? micFile?.write(from: converted)
        _ = file
    }

    private func startSystemAudio(in folder: URL) async throws {
        guard await ensureScreenCaptureAccess() else {
            throw RecorderError.permission(Self.screenCaptureHelp)
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if CGPreflightScreenCaptureAccess() {
                throw error
            }
            throw RecorderError.permission(Self.screenCaptureHelp)
        }
        guard let display = content.displays.first else { throw RecorderError.noDisplay }

        let bundleID = Bundle.main.bundleIdentifier
        let excluded = content.applications.filter { $0.bundleIdentifier == bundleID }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = Int(sampleRate)
        configuration.channelCount = Int(channels)
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: audioQueue)
        try await stream.startCapture()

        let file = try AVAudioFile(forWriting: folder.appendingPathComponent("system.caf"), settings: targetFormat.settings)
        lock.lock()
        self.stream = stream
        self.systemFile = file
        lock.unlock()
    }

    private static let screenCaptureHelp = """
    Нет доступа к звуку компьютера. Переключатель в настройках может быть включён для старой сборки: macOS тогда молча отказывает и не спрашивает снова.

    Системные настройки → Конфиденциальность и безопасность → «Запись экрана и системного звука»: выключи MeetRec, включи снова. Если есть отдельный пункт «Запись системного звука», включи MeetRec и там. Полностью закрой приложение и открой его заново. Картинка не сохраняется.
    """

    private func ensureScreenCaptureAccess() async -> Bool {
        await MainActor.run {
            if CGPreflightScreenCaptureAccess() { return true }
            if CGRequestScreenCaptureAccess() { return true }
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return false
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let buffer = pcmBuffer(from: sampleBuffer), let converted = convertSystem(buffer) else { return }
        lock.lock()
        defer { lock.unlock() }
        try? systemFile?.write(from: converted)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        isRecording = false
        lock.unlock()
    }

    private func stopSystemAudio() async {
        lock.lock()
        let stream = self.stream
        self.stream = nil
        lock.unlock()
        if let stream {
            try? await stream.stopCapture()
        }
        lock.lock()
        systemFile = nil
        lock.unlock()
    }

    private func stopMicrophone() {
        lock.lock()
        let engine = self.engine
        self.engine = nil
        micConverter = nil
        micFile = nil
        lock.unlock()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
    }

    private func teardown() {
        Task { await stopSystemAudio() }
        stopMicrophone()
        lock.lock()
        isRecording = false
        if let sessionFolder {
            try? FileManager.default.removeItem(at: sessionFolder)
        }
        sessionFolder = nil
        lock.unlock()
    }

    private func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var used = false
        converter.convert(to: output, error: &error) { _, status in
            if used {
                status.pointee = .noDataNow
                return nil
            }
            used = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    private func convertSystem(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format.sampleRate == targetFormat.sampleRate,
           buffer.format.channelCount == targetFormat.channelCount,
           buffer.format.commonFormat == .pcmFormatFloat32 {
            return buffer
        }
        lock.lock()
        let existing = micConverter
        lock.unlock()
        _ = existing
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }
        return convert(buffer, with: converter)
    }

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return nil }
        let format = AVAudioFormat(streamDescription: basic)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }

    private func mix(mode: CaptureMode, folder: URL, to output: URL) throws {
        let micURL = folder.appendingPathComponent("mic.caf")
        let systemURL = folder.appendingPathComponent("system.caf")
        switch mode {
        case .microphone:
            try exportWAV(from: micURL, to: output)
        case .system:
            try exportWAV(from: systemURL, to: output)
        case .both:
            try exportMix(mic: micURL, system: systemURL, to: output)
        }
    }

    private func exportWAV(from source: URL, to output: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let wav = try wavFile(at: output)
        try copy(input, to: wav)
    }

    private func exportMix(mic: URL, system: URL, to output: URL) throws {
        let micFile = try AVAudioFile(forReading: mic)
        let systemFile = try AVAudioFile(forReading: system)
        let wav = try wavFile(at: output)
        let capacity: AVAudioFrameCount = 48_000
        guard let micBuffer = AVAudioPCMBuffer(pcmFormat: micFile.processingFormat, frameCapacity: capacity),
              let systemBuffer = AVAudioPCMBuffer(pcmFormat: systemFile.processingFormat, frameCapacity: capacity),
              let mixed = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw RecorderError.permission("Не хватило памяти, чтобы собрать файл.")
        }

        var micDone = false
        var systemDone = false
        while !micDone || !systemDone {
            micBuffer.frameLength = 0
            systemBuffer.frameLength = 0
            if !micDone {
                do { try micFile.read(into: micBuffer) } catch { micDone = true }
                if micBuffer.frameLength == 0 { micDone = true }
            }
            if !systemDone {
                do { try systemFile.read(into: systemBuffer) } catch { systemDone = true }
                if systemBuffer.frameLength == 0 { systemDone = true }
            }
            let frames = max(micBuffer.frameLength, systemBuffer.frameLength)
            if frames == 0 { break }
            mixed.frameLength = frames
            guard let left = mixed.floatChannelData?[0], let right = mixed.floatChannelData?[1] else { break }
            for frame in 0..<Int(frames) {
                let micSample = sample(micBuffer, frame: frame)
                let systemSample = sample(systemBuffer, frame: frame)
                let value = clamp(micSample + systemSample)
                left[frame] = value
                right[frame] = value
            }
            try writeBuffer(mixed, to: wav)
        }
    }

    private func copy(_ input: AVAudioFile, to output: AVAudioFile) throws {
        let capacity: AVAudioFrameCount = 48_000
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: capacity) else { return }
        while true {
            buffer.frameLength = 0
            do { try input.read(into: buffer) } catch { break }
            if buffer.frameLength == 0 { break }
            try writeBuffer(buffer, to: output)
        }
    }

    private func wavFile(at url: URL) throws -> AVAudioFile {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        return try AVAudioFile(forWriting: url, settings: settings)
    }

    private func writeBuffer(_ buffer: AVAudioPCMBuffer, to file: AVAudioFile) throws {
        let outputFormat = file.processingFormat
        if buffer.format == outputFormat {
            if buffer.frameLength > 0 {
                try file.write(from: buffer)
            }
            return
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
            throw RecorderError.permission("Не получилось подготовить файл WAV.")
        }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: max(capacity, 64)) else { return }
        var error: NSError?
        var used = false
        converter.convert(to: output, error: &error) { _, status in
            if used {
                status.pointee = .noDataNow
                return nil
            }
            used = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        if output.frameLength > 0 {
            try file.write(from: output)
        }
    }

    private func sample(_ buffer: AVAudioPCMBuffer, frame: Int) -> Float {
        guard frame < Int(buffer.frameLength), let channels = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.format.channelCount)
        if count == 0 { return 0 }
        var sum: Float = 0
        for channel in 0..<count {
            sum += channels[channel][frame]
        }
        return sum / Float(count)
    }

    private func clamp(_ value: Float) -> Float {
        min(1, max(-1, value))
    }

    private func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }
}
