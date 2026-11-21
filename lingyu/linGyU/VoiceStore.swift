import AVFoundation
import Combine
import Speech

/// Voice preference keys (UserDefaults). One place, so the call, the
/// hold-to-talk composer and the voice settings page agree.
enum VoicePrefs {
    /// "device" (on-device speech) — the only engine that works while the
    /// computer's credential store is locked. "openai" / "gemini" are
    /// stored only; the settings page keeps them disabled until the host
    /// vault unlocks and a key can be saved.
    static let engine = "cn.lingyu.voiceEngine"
    /// Reading speed (AVSpeechUtterance rate).
    static let rate = "cn.lingyu.callRate"
    /// Silence (seconds) that ends an utterance and sends it.
    static let pause = "cn.lingyu.callPause"
    /// Whether a call reads the bot's replies aloud automatically.
    static let autoReadAloud = "cn.lingyu.autoReadAloud"
}

/// One line of a call's conversation.
struct CallLine: Identifiable, Equatable {
    enum Speaker: String {
        /// The user, transcribed on this device.
        case user
        /// The bot, read aloud (or shown as text when reading is off).
        case agent
    }

    var id = UUID()
    var speaker: Speaker
    var text: String
    var at: Date

    init(speaker: Speaker, text: String, at: Date = Date()) {
        self.speaker = speaker
        self.text = text
        self.at = at
    }
}

/// A call's state machine: idle → connecting → live → ended (or failed).
enum VoiceCallPhase: Equatable {
    case idle
    case connecting
    case live
    case ended
    case failed(String)
}

/// One on-device voice call with a bot: the microphone is transcribed on
/// this phone (SFSpeechRecognizer), the text goes to the bot as an ordinary
/// chat message, and the bot's final replies are read aloud with Edge
/// Xiaoxiao (free online voice, the app's only voice). No host key is
/// involved — the computer's credential store is locked, so the realtime /
/// Live engines are unavailable and this is the only engine a call can use.
/// When there is no network, replies are skipped silently: no system voice,
/// no offline model, no error popup.
@MainActor
final class VoiceStore: ObservableObject {
    let botId: String
    let botName: String
    private let store: AppStore

    @Published private(set) var phase: VoiceCallPhase = .idle
    /// Microphone loudness, 0…1, while listening (drives the avatar pulse).
    @Published private(set) var level: Float = 0
    /// What the user is saying right now (live caption).
    @Published private(set) var heard = ""
    /// The call's conversation so far, oldest first.
    @Published private(set) var lines: [CallLine] = []
    /// Whether the bot's reply is being read aloud right now.
    @Published private(set) var isSpeaking = false
    @Published private(set) var elapsedSeconds = 0
    @Published var muted = false {
        didSet {
            guard muted != oldValue, phase == .live else { return }
            if muted { stopListening() } else { listen() }
            Task {
                await LiveActivityManager.shared.updateCall(
                    botId: botId, step: muted ? L("静音") : L("正在听"),
                    status: "working", muted: muted)
            }
        }
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private lazy var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var generation = 0
    private var consecutiveFailures = 0
    private var silenceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private let edgePlayer = EdgeTTSPlayer()
    private var synthTask: Task<Void, Never>?
    private var speechQueue: [String] = []
    private var spokenEntryIds: Set<String> = []
    private var startedAtMillis: Int64 = 0
    private var startedAt: Date?
    private var greetingSpoken = false
    private var ended = false

    /// Seconds of silence that end an utterance and send it.
    private var endOfUtterance: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: VoicePrefs.pause)
        return saved > 0 ? saved : 1.5
    }

    private var autoReadAloud: Bool {
        UserDefaults.standard.object(forKey: VoicePrefs.autoReadAloud) as? Bool ?? false
    }

    init(store: AppStore, botId: String, botName: String) {
        self.store = store
        self.botId = botId
        self.botName = botName
    }

    // MARK: - Start / end

    func start() async {
        guard phase == .idle else { return }
        phase = .connecting
        guard await AVAudioApplication.requestRecordPermission() else {
            return fail(L("需要麦克风权限才能通话，请在系统设置里开启。"))
        }
        guard await Self.speechAuthorized() else {
            return fail(L("需要语音识别权限才能通话，请在系统设置里开启。"))
        }
        guard let recognizer, recognizer.isAvailable else {
            return fail(L("这台设备上语音识别不可用。"))
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return fail(L("无法启动音频：%@。", error.localizedDescription))
        }
        startedAt = Date()
        startedAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
        phase = .live
        let bot = store.connector.mirror.bot(id: botId)
        LiveActivityManager.shared.startCall(
            botId: botId, name: botName,
            avatarShape: bot?.avatarShape ?? "", avatarColor: bot?.avatarColor ?? "",
            step: L("正在听"))
        greet()
        listen()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                if let startedAt { elapsedSeconds = Int(Date().timeIntervalSince(startedAt)) }
            }
        }
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                pollBotReplies()
            }
        }
    }

    /// Ends the call. Idempotent: safe to call from both the hang-up
    /// button and the view's disappearance.
    func end() {
        guard !ended else { return }
        ended = true
        pollTask?.cancel()
        timerTask?.cancel()
        silenceTask?.cancel()
        pollTask = nil
        timerTask = nil
        silenceTask = nil
        speechQueue.removeAll()
        synthTask?.cancel()
        synthTask = nil
        edgePlayer.stop()
        stopListening()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isSpeaking = false
        phase = .ended
        Task { await LiveActivityManager.shared.endCall(botId: botId) }
    }

    /// Cuts the reply short and goes back to listening.
    func interrupt() {
        guard isSpeaking else { return }
        speechQueue.removeAll()
        synthTask?.cancel()
        synthTask = nil
        edgePlayer.stop()
        isSpeaking = false
        listen()
    }

    private func fail(_ message: String) {
        stopListening()
        phase = .failed(message)
        Task { await LiveActivityManager.shared.endCall(botId: botId) }
    }

    static func speechAuthorized() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Greeting

    /// The lead bot speaks first when the call connects.
    private func greet() {
        guard !greetingSpoken else { return }
        greetingSpoken = true
        let greeting = L("你好，我是 %@，有什么可以帮你的吗？", botName)
        lines.append(CallLine(speaker: .agent, text: greeting))
        if autoReadAloud {
            speak(sentences: [greeting])
        }
    }

    // MARK: - Listening

    private func listen() {
        guard !ended, !muted, phase == .live, let recognizer else { return }
        heard = ""
        generation += 1
        let currentGeneration = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        do {
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format,
                             block: Self.tap(request) { [weak self] level in
                                 Task { @MainActor in self?.level = level }
                             })
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            fail(L("无法使用麦克风：%@。", error.localizedDescription))
            return
        }
        recognitionTask = recognizer.recognitionTask(with: request,
                                                     resultHandler: Self.results(self, generation: currentGeneration))
    }

    private func stopListening() {
        silenceTask?.cancel()
        silenceTask = nil
        generation += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        level = 0
    }

    fileprivate func recognized(_ text: String, final: Bool, generation: Int) {
        guard generation == self.generation, phase == .live else { return }
        heard = text
        if !text.isEmpty { consecutiveFailures = 0 }
        silenceTask?.cancel()
        if final { return submit() }
        silenceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(endOfUtterance * 1_000_000_000))
            guard !Task.isCancelled else { return }
            submit()
        }
    }

    private func submit() {
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening()
        if !text.isEmpty {
            lines.append(CallLine(speaker: .user, text: text))
            sendToBot(text)
        }
        listen()
    }

    fileprivate func recognitionFailed(generation: Int) {
        guard generation == self.generation, phase == .live else { return }
        consecutiveFailures += 1
        // A single hiccup resubmits what was heard and listens again;
        // repeated immediate failures end the call with a reason instead
        // of showing "listening" forever while hearing nothing.
        if consecutiveFailures >= 3 {
            let unheard = L("一直听不到声音，通话已结束。")
            if !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { submit() }
            fail(unheard)
            return
        }
        submit()
    }

    private func sendToBot(_ text: String) {
        guard let api = store.connector.api else { return }
        let nonce = UUID().uuidString
        let local = Entry(localText: text, botId: botId, clientNonce: nonce)
        store.connector.mirror.addLocalEntry(local)
        Task {
            do {
                _ = try await api.send(botId: botId, text: text, clientNonce: nonce)
            } catch {
                store.connector.mirror.updateLocalEntry(botId: botId, clientNonce: nonce, status: "failed")
            }
        }
    }

    // MARK: - Bot replies

    /// New final agent messages since the call started are read aloud,
    /// sentence by sentence, and added to the call's lines.
    private func pollBotReplies() {
        guard phase == .live, !ended else { return }
        let entries = store.connector.mirror.entries(for: botId)
        for entry in entries where entry.kind == "agent" && entry.data.final == true {
            guard entry.createdAt > startedAtMillis,
                  !spokenEntryIds.contains(entry.id),
                  let text = entry.data.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            spokenEntryIds.insert(entry.id)
            lines.append(CallLine(speaker: .agent, text: text))
            if autoReadAloud {
                speak(sentences: Self.sentences(of: text))
            }
        }
    }

    /// Splits a reply into speakable sentences (Chinese and Western stops).
    static func sentences(of text: String) -> [String] {
        let stops = CharacterSet(charactersIn: "。！？；\n.!?;")
        var sentences: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            current.unicodeScalars.append(scalar)
            if stops.contains(scalar) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences.isEmpty ? [text] : sentences
    }

    // MARK: - Speaking

    private func speak(sentences: [String]) {
        guard !ended, phase == .live, !sentences.isEmpty else { return }
        speechQueue.append(contentsOf: sentences)
        if !isSpeaking { speakNext() }
    }

    private func speakNext() {
        guard !ended, phase == .live, !speechQueue.isEmpty else {
            isSpeaking = false
            return
        }
        stopListening()
        synthTask?.cancel()
        edgePlayer.stop()
        let text = speechQueue.removeFirst()
        isSpeaking = true
        let savedRate = UserDefaults.standard.float(forKey: VoicePrefs.rate)
        let avRate: Float = savedRate > 0 ? savedRate : AVSpeechUtteranceDefaultSpeechRate
        synthTask = Task {
            do {
                let data = try await EdgeTTS.Synthesizer().synthesize(
                    text: text, voice: .xiaoxiao, avRate: avRate)
                guard !Task.isCancelled else { return }
                let played = self.edgePlayer.play(data) { [weak self] in
                    Task { @MainActor in self?.finishedSpeaking() }
                }
                if !played {
                    self.finishedSpeaking()
                }
            } catch {
                // Cancelled by interrupt()/end()/the next sentence: that
                // caller already handled the state, so stay out of it.
                if Task.isCancelled { return }
                // Edge needs the network: offline or a failed request just
                // skips this sentence silently — never the system voice,
                // never an error popup. The queue moves on.
                self.finishedSpeaking()
            }
        }
    }

    private func finishedSpeaking() {
        guard phase == .live, !ended else { return }
        if speechQueue.isEmpty {
            isSpeaking = false
            listen()
        } else {
            speakNext()
        }
    }

    // MARK: - Audio-thread closures (built outside the main actor)

    /// Feeds the recognizer and reports the microphone's level, 0…1.
    nonisolated static func tap(_ request: SFSpeechAudioBufferRecognitionRequest,
                                meter: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += samples[i] * samples[i] }
            // -50 dB (quiet room) … 0 dB mapped to 0…1.
            let db = 10 * log10(max(sum / Float(n), 1e-10))
            meter(min(1, max(0, (db + 50) / 50)))
        }
    }

    private nonisolated static func results(_ session: VoiceStore, generation: Int)
        -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                if let text { session.recognized(text, final: final, generation: generation) }
                if failed { session.recognitionFailed(generation: generation) }
            }
        }
    }
}

// MARK: - One-shot recognition (hold to talk in the composer)

/// A single press-and-hold utterance: start on press, stop on release,
/// and hand the recognised text back for the input field (never sends).
/// Falls back to the keyboard's dictation when it cannot start.
@MainActor
final class OneShotSpeechRecognizer: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var interimText = ""
    @Published private(set) var isRecording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private lazy var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestText = ""
    private var finalText: String?
    private var finishedContinuation: CheckedContinuation<String, Never>?

    /// Starts listening. Returns false when a permission is missing or
    /// recognition is unavailable — the caller then falls back to the
    /// keyboard's dictation.
    func start() async -> Bool {
        guard !isRecording else { return true }
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        guard await VoiceStore.speechAuthorized() else { return false }
        guard let recognizer, recognizer.isAvailable else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth])
            try session.setActive(true)
        } catch {
            return false
        }
        latestText = ""
        interimText = ""
        finalText = nil
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        do {
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format,
                             block: VoiceStore.tap(request) { [weak self] level in
                                 Task { @MainActor in self?.level = level }
                             })
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            return false
        }
        isRecording = true
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if !text.isEmpty {
                    self.latestText = text
                    self.interimText = text
                }
                if final {
                    self.finalText = text
                    self.finishRecording()
                } else if error != nil {
                    self.finishRecording()
                }
            }
        }
        return true
    }

    /// Stops and returns the recognised text (empty when nothing was heard).
    func finish() async -> String {
        guard isRecording else { return finalText ?? latestText }
        request?.endAudio()
        // The final result may already have landed between endAudio and
        // this line; don't wait for a continuation that will never fire.
        if !isRecording { return finalText ?? latestText }
        return await withCheckedContinuation { continuation in
            finishedContinuation = continuation
            // The final result usually arrives within a moment; if the
            // recognizer never delivers one, hand back what was heard.
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    if let pending = self.finishedContinuation {
                        self.finishedContinuation = nil
                        self.finishRecording()
                        pending.resume(returning: self.latestText)
                    }
                }
            }
        }
    }

    /// Discards the utterance.
    func cancel() {
        finishedContinuation = nil
        finishRecording()
    }

    private func finishRecording() {
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        level = 0
        if let pending = finishedContinuation {
            finishedContinuation = nil
            pending.resume(returning: finalText ?? latestText)
        }
    }
}
