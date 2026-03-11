import AVFoundation
import Combine
import Speech

@MainActor
final class AudioCaptureService: ObservableObject {
    @Published var liveTranscript: String = ""

    private let audioEngine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isListening = false

    private static let localeMap: [String: String] = [
        "Turkish": "tr-TR", "English": "en-US", "German": "de-DE",
        "French": "fr-FR", "Spanish": "es-ES", "Italian": "it-IT",
        "Portuguese": "pt-BR", "Japanese": "ja-JP", "Korean": "ko-KR", "Chinese": "zh-CN"
    ]

    init() {
        let language = UserDefaults.standard.string(forKey: "app.language") ?? "Turkish"
        let identifier = Self.localeMap[language] ?? "tr-TR"
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
    }

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let mic = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return speech && mic
    }

    func startListening() throws {
        guard !isListening else { return }           // prevent double-start
        guard let recognizer, recognizer.isAvailable else {
            throw AudioServiceError.recognizerUnavailable
        }

        // 1. Configure and activate AVAudioSession
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // 2. Reset state
        liveTranscript = ""
        task?.cancel()
        task = nil

        // 3. Set up recognition request
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        // 4. Install audio tap
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let format = inputNode.outputFormat(forBus: 0)
        // Validate format — a 0 sample rate means audio session isn't ready
        guard format.sampleRate > 0 else {
            throw AudioServiceError.invalidAudioFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        // 5. Start engine
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        // 6. Start recognition — dispatch stopListening back to MainActor
        guard let request else { return }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let transcript = result?.bestTranscription.formattedString {
                Task { @MainActor in
                    self.liveTranscript = transcript
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in       // ← CRITICAL: always hop to MainActor
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }   // guard against double-stop
        isListening = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        // Deactivate session so other apps can resume audio
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum AudioServiceError: LocalizedError {
    case recognizerUnavailable
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available for the selected language. Change it in Settings → Language."
        case .invalidAudioFormat:
            return "Microphone audio format is invalid. Please check microphone permissions."
        }
    }
}
