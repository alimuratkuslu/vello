import AppKit
import AVFoundation // AVCaptureDevice authorization
import ApplicationServices
import WhisperKit

/// One dictation: hold the talk key → record → release → transcribe → paste into the focused field.
@MainActor
final class Dictation: ObservableObject {
    enum State { case loading, idle, listening, transcribing, error }

    @Published private(set) var state: State = .loading { didSet { updateIndicator() } }
    @Published private(set) var levels = [Float](repeating: 0, count: 12)
    @Published private(set) var flashError: String? { didSet { updateIndicator() } }
    @Published private(set) var lastText: String?
    /// Paused: app stays open, the talk key does nothing. Not persisted; every launch starts active.
    @Published var paused = false

    // Setup state, shown in the settings window.
    @Published private(set) var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published private(set) var axTrusted = AXIsProcessTrusted()
    @Published private(set) var modelReady = false
    @Published private(set) var modelStatus = String(localized: "Preparing…")
    @Published private(set) var modelProgress: Double?
    @Published private(set) var axRequested = false

    private var whisper: WhisperKit?
    private var pressedAt = Date()
    private var monitors: [Any] = []
    private var levelTimer: Timer?
    private lazy var indicator = Indicator(dictation: self)

    // Chunks transcribed while still listening, so release only waits for the tail.
    private var committed = 0                 // samples already sent for transcription
    private var chunkTexts: [String] = []
    private var chunkTask: Task<Void, Never>?
    private var session = 0                   // bumps on every start/cancel; stale chunk results are dropped

    private static let model = "openai*large-v3-v20240930_turbo_632MB"
    private static let minDuration: TimeInterval = 0.3
    // Tail cost ≈ 0.4 s + ~11 ms per prompt/output token (prompt tokens are decoded one by one), so keep the tail short.
    private static let chunkSeconds = 7       // start a background chunk once this much audio is untranscribed
    private static let cutSearchSeconds = 2   // cut at the quietest 100 ms within the last 2 s, ideally a pause between words

    var icon: String {
        switch state {
        case .loading: "hourglass"
        case .idle: paused || !canDictate ? "waveform.slash" : "waveform"
        case .listening: "mic.fill"
        case .transcribing: "ellipsis"
        case .error: "exclamationmark.triangle"
        }
    }

    var canDictate: Bool { micGranted && axTrusted && Settings.language != nil }

    /// Menu shows nothing when everything works; only what blocks dictation.
    var menuStatus: String? {
        if !modelReady { return String(localized: "Speech model: \(modelStatus)") }
        if !canDictate { return String(localized: "Setup isn’t finished") }
        return nil
    }

    init() {
        Task { await loadModel() }
        if axTrusted { startMonitoring() }
        // Permissions can be granted (or revoked) in System Settings at any time; reflect that without a restart.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    private func loadModel() async {
        do {
            // Own folder instead of WhisperKit's default ~/Documents, which would trigger a Documents access prompt.
            let base = Vocabulary.url.deletingLastPathComponent().appendingPathComponent("models")
            // Skip the network once downloaded: works offline and doesn't flash "Downloading" on every launch.
            let marker = base.appendingPathComponent(".downloaded")
            var folder = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo_632MB")
            if !FileManager.default.fileExists(atPath: marker.path) {
                modelStatus = String(localized: "Downloading (~600 MB)…")
                folder = try await WhisperKit.download(variant: Self.model, downloadBase: base) { progress in
                    Task { @MainActor in
                        self.modelProgress = progress.fractionCompleted
                        self.modelStatus = String(localized: "Downloading: \(Int(progress.fractionCompleted * 100))% (~600 MB)")
                    }
                }
                modelProgress = nil
                modelStatus = String(localized: "Preparing (first launch only, takes a few minutes)…")
            }
            // Tokenizer next to the model too, not in WhisperKit's default ~/Documents.
            let whisper = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, tokenizerFolder: base, verbose: false, prewarm: true, load: true, download: false))
            FileManager.default.createFile(atPath: marker.path, contents: nil) // only after a successful load, so a cut-off download is retried
            _ = try? await whisper.transcribe(audioArray: [Float](repeating: 0, count: WhisperKit.sampleRate)) // warm-up so the first dictation isn't slower
            self.whisper = whisper
            modelReady = true
            state = .idle
        } catch {
            modelStatus = String(localized: "Couldn’t load: \(error.localizedDescription)")
            state = .error
        }
    }

    private func refreshPermissions() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let ax = AXIsProcessTrusted()
        // A grant happens in a system dialog or System Settings, which leaves our window behind; bring it back.
        if mic != micGranted {
            micGranted = mic
            if mic { SettingsWindow.bringToFront() }
        }
        if ax != axTrusted {
            axTrusted = ax
            if ax { startMonitoring(); SettingsWindow.bringToFront() }
        }
        if Settings.setupDone && (!mic || !ax) && !wasPromptedForRevoke {
            wasPromptedForRevoke = true // reopen the window once per revoke, not every second
            SettingsWindow.show(self)
        }
        if mic && ax { wasPromptedForRevoke = false }
    }
    private var wasPromptedForRevoke = false

    func requestMic() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            // AVCaptureDevice, not WhisperKit's AVAudioApplication request: on macOS that one could report a grant
            // that authorizationStatus (and recording) didn't see, so the row flipped back to "Allow".
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in self.refreshPermissions(); SettingsWindow.bringToFront() }
            }
        default:
            // The system only asks once; after a denial the switch lives in System Settings.
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    func requestAccessibility() {
        if axRequested {
            // The system alert only shows once; later clicks go straight to the right pane.
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            // Adds Vello to the Accessibility list and shows the system alert with an "Open System Settings" button.
            let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(prompt)
            axRequested = true
        }
    }

    private func startMonitoring() {
        guard monitors.isEmpty else { return }
        _ = indicator // build the panel now so the first dictation doesn't pay for it
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handler) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { handler($0); return $0 } as Any)
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            // Key+letter is a shortcut or character (e.g. Option+Q = @ on Turkish Q), not a dictation.
            if state == .listening { cancel() }
            return
        }
        let key = Settings.talkKey
        guard event.keyCode == key.keyCode else { return }
        if key.isDown(event.modifierFlags) {
            guard !paused && canDictate else { return }
            if modelReady { start() } else { flash(String(localized: "Speech model is still getting ready")) }
        } else {
            stop()
        }
    }

    private func start() {
        guard state == .idle, let whisper else { return } // presses while transcribing are ignored
        session += 1
        committed = 0
        chunkTexts = []
        chunkTask = nil
        pressedAt = Date()
        state = .listening // indicator first: opening the mic takes 100-300 ms, so it starts on the next run loop turn
        let id = session
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .listening, self.session == id else { return }
            do {
                try whisper.audioProcessor.startRecordingLive(inputDeviceID: Settings.micMode.deviceID(), callback: nil)
                self.levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.updateLevels()
                        self?.transcribeChunkIfReady()
                    }
                }
            } catch {
                self.state = .idle
                self.flash(String(localized: "Couldn’t open the microphone"))
            }
        }
    }

    private func cancel() {
        session += 1
        chunkTask = nil
        stopRecording()
        state = .idle
    }

    private func stopRecording() {
        levelTimer?.invalidate()
        levels = levels.map { _ in 0 }
        whisper?.audioProcessor.stopRecording()
    }

    private func updateLevels() {
        guard let energy = whisper?.audioProcessor.relativeEnergy, !energy.isEmpty else { return }
        let recent = energy.suffix(levels.count)
        levels = [Float](repeating: 0, count: levels.count - recent.count) + recent.map { min(max($0, 0), 1) }
    }

    private func transcribeChunkIfReady() {
        guard chunkTask == nil, let whisper else { return }
        let samples = whisper.audioProcessor.audioSamples
        let rate = WhisperKit.sampleRate
        guard samples.count - committed >= Self.chunkSeconds * rate else { return }
        let cut = Self.quietestPoint(in: samples, from: samples.count - Self.cutSearchSeconds * rate, to: samples.count)
        let chunk = Self.speech(in: samples[committed..<cut], peak: Self.peakRMS(samples[...]))
        committed = cut
        let id = session
        chunkTask = Task {
            let text = chunk.isEmpty ? "" : await transcribe(chunk, with: whisper)
            guard id == session else { return }
            chunkTexts.append(text)
            chunkTask = nil
        }
    }

    /// Leading/trailing near-silence trimmed; empty if under 0.3 s of speech remains.
    /// Silent tails made Whisper retry up to 5 times (~3 s) and return nothing.
    private static func speech(in audio: ArraySlice<Float>, peak: Float) -> [Float] {
        // shortcut: silence = below 3% of the dictation's loudest 100 ms (or an absolute floor); 10% dropped a real 4 s tail once.
        let threshold = max(peak * 0.03, 0.001)
        let frame = WhisperKit.sampleRate / 10
        let starts = Array(stride(from: audio.startIndex, to: audio.endIndex, by: frame))
        let loud = starts.filter { rms(audio[$0..<min($0 + frame, audio.endIndex)]) >= threshold }
        guard let first = loud.first, let last = loud.last else { return [] }
        // keep 100 ms of padding on each side so word edges aren't clipped
        let from = max(first - frame, audio.startIndex), to = min(last + 2 * frame, audio.endIndex)
        return to - from >= frame * 3 ? Array(audio[from..<to]) : []
    }

    private static func peakRMS(_ samples: ArraySlice<Float>) -> Float {
        let frame = WhisperKit.sampleRate / 10
        return stride(from: samples.startIndex, to: samples.endIndex, by: frame).map { rms(samples[$0..<min($0 + frame, samples.endIndex)]) }.max() ?? 0
    }

    private static func rms(_ frame: ArraySlice<Float>) -> Float {
        frame.isEmpty ? 0 : (frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)).squareRoot()
    }

    /// Middle of the 100 ms frame with the least energy in [from, to).
    private static func quietestPoint(in samples: ContiguousArray<Float>, from: Int, to: Int) -> Int {
        let frame = WhisperKit.sampleRate / 10
        var best = to, bestEnergy = Float.infinity
        var i = from
        while i + frame <= to {
            var energy: Float = 0
            for j in i..<(i + frame) { energy += samples[j] * samples[j] }
            if energy < bestEnergy { bestEnergy = energy; best = i + frame / 2 }
            i += frame
        }
        return best
    }

    private func updateIndicator() {
        if state == .listening || state == .transcribing || flashError != nil { indicator.show() } else { indicator.hide() }
    }

    /// Short red message in the indicator for errors during a dictation; setup errors stay in the menu only.
    private func flash(_ message: String) {
        flashError = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.flashError = nil }
    }

    private func stop() {
        guard state == .listening, let whisper else { return }
        stopRecording()
        let samples = Array(whisper.audioProcessor.audioSamples)
        guard Date().timeIntervalSince(pressedAt) >= Self.minDuration else { return cancel() }
        state = .transcribing
        let id = session
        let pending = chunkTask
        Task {
            await pending?.value
            guard id == session else { return }
            let tail = committed < samples.count ? Self.speech(in: samples[committed...], peak: Self.peakRMS(samples[...])) : []
            let tailText = tail.isEmpty ? "" : await transcribe(tail, with: whisper)
            let text = (chunkTexts + [tailText]).filter { !$0.isEmpty }.joined(separator: " ")
            if !text.isEmpty {
                lastText = text
                Paster.paste(text)
            }
            state = .idle
        }
    }

    private func transcribe(_ samples: [Float], with whisper: WhisperKit) async -> String {
        // At most one temperature fallback: up to 5 retries took ~3 s on hard chunks without better text.
        var options = DecodingOptions(task: .transcribe, language: Settings.language ?? "tr", temperatureFallbackCount: 1, usePrefillPrompt: true,
                                      skipSpecialTokens: true, withoutTimestamps: true, chunkingStrategy: .vad)
        // No previous-chunk context in the prompt: measured +25 tokens ≈ +0.3 s on the tail for little boundary gain.
        let prompt = Vocabulary.prompt()
        if !prompt.isEmpty, let tokenizer = whisper.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        do {
            let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
            return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            flash(String(localized: "Transcription failed"))
            return ""
        }
    }

}

enum Paster {
    /// Clipboard + Cmd+V works in every app and handles Turkish characters; the user's clipboard is restored afterwards.
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // shortcut: virtual key 9 is "V" on ANSI/Turkish Q layouts, not Turkish F; switch to a layout lookup if F users appear.
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        // shortcut: fixed 0.5 s for the target app to read the clipboard; raise it if slow apps paste the old content.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved)
        }
    }
}
