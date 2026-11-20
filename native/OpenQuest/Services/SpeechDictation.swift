import AVFoundation
import Speech

/// 系统听写：SFSpeechRecognizer + AVAudioEngine。
/// 点一下开始，实时把识别文字流进输入框（liveText）；点一下停止。
/// 当前语言无识别器、或用户拒绝权限时 canDictate 为 false，首页不画语音按钮；
/// 权限被拒当次弹一次去系统设置的提示（showPermissionAlert），不静默失败。
@MainActor
final class SpeechDictation: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    /// 语音按钮是否可画：识别器可用、且权限不是已拒/受限（未询问时为 true，点按才触发系统授权）。
    @Published private(set) var canDictate = false
    /// 本轮识别出的文字（部分结果实时更新，最终结果后停止）。
    @Published private(set) var liveText = ""
    /// 权限被拒后弹一次“去系统设置开权限”的提示。
    @Published var showPermissionAlert = false

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        // 中文优先；当前设备不支持中文识别时退回系统默认语言的识别器。
        if let zh = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN")) {
            recognizer = zh
        } else {
            recognizer = SFSpeechRecognizer()
        }
        recognizer?.delegate = self
        refreshAvailability()
    }

    /// 刷新按钮可见性：识别器不存在/不可用、或权限已拒/受限 → 不画按钮。
    func refreshAvailability() {
        guard let recognizer, recognizer.isAvailable else {
            canDictate = false
            return
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            canDictate = false
        case .authorized, .notDetermined:
            canDictate = true
        @unknown default:
            canDictate = false
        }
    }

    /// 点按入口：先要麦克风权限，再要语音识别权限，都通过才开始录音识别。
    func start() {
        guard !isRecording, let recognizer, recognizer.isAvailable else { return }
        AVAudioApplication.requestRecordPermission { [weak self] micGranted in
            Task { @MainActor in
                guard let self else { return }
                guard micGranted else {
                    self.canDictate = false
                    self.showPermissionAlert = true
                    return
                }
                SFSpeechRecognizer.requestAuthorization { status in
                    Task { @MainActor in
                        switch status {
                        case .authorized:
                            self.beginRecording()
                        case .denied, .restricted:
                            self.canDictate = false
                            self.showPermissionAlert = true
                        case .notDetermined:
                            self.canDictate = false
                        @unknown default:
                            self.canDictate = false
                        }
                    }
                }
            }
        }
    }

    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecording() {
        guard let recognizer, recognizer.isAvailable else { return }
        stop() // 兜底：先停掉上一轮残留
        liveText = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            return
        }
        audioEngine = engine
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.liveText = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stop()
                        return
                    }
                }
                if error != nil {
                    self.stop()
                }
            }
        }
        isRecording = true
    }
}

extension SpeechDictation: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in self.refreshAvailability() }
    }
}
