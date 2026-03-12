import AVFoundation
import Combine
import Speech

// MARK: - SFSpeechRecognizer Limitations
//
// 1. Server-based recognition (default): Apple limits requests to ~1 minute.
//    When `isFinal` fires, we automatically restart the recognition task while
//    keeping the audio engine and file recording running. Transcripts are
//    accumulated across restarts.
//
// 2. On-device recognition: Available on iOS 16+ for some languages. No time
//    limit, but slightly less accurate. Enable with:
//    request.requiresOnDeviceRecognition = true
//
// 3. Audio session conflict: Setting .record category mutes other audio.
//    On stopListening() we deactivate the session so system audio resumes.
//
// 4. Audio format: We write raw PCM to .caf files (native AVAudioEngine format).
//    Files are larger than AAC but always work without transcoding. For smaller
//    files, use AVAssetExportSession to convert to .m4a after recording.

@MainActor
protocol SpeechListeningService: AnyObject {
    var currentTranscript: String { get }
    var liveTranscriptPublisher: AnyPublisher<String, Never> { get }
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }
    var currentRecordingURL: URL? { get }
    func requestPermissions() async -> Bool
    func startListening(for projectId: String) throws
    func startListening() throws   // backward compat — calls startListening(for: "")
    func stopListening() -> URL?   // returns audio file URL (nil if no file)
}

@MainActor
final class AudioCaptureService: ObservableObject {
    @Published var liveTranscript: String = ""
    @Published var audioLevel: Float = 0

    private let audioEngine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isListening = false
    private var accumulatedTranscript = ""

    // File recording
    private var audioFile: AVAudioFile?
    private(set) var currentRecordingURL: URL?
    private var currentProjectId: String = ""
    private var levelSampleCounter = 0

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

    func startListening(for projectId: String) throws {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw AudioServiceError.recognizerUnavailable
        }

        currentProjectId = projectId
        liveTranscript = ""
        accumulatedTranscript = ""

        // Configure AVAudioSession
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Create audio file in project-scoped folder
        let fileURL = try makeAudioFileURL(projectId: projectId)
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw AudioServiceError.invalidAudioFormat }

        audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        currentRecordingURL = fileURL

        // Install single tap: feeds recognition + file + level meter
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            try? self?.audioFile?.write(from: buffer)
            self?.processSampleLevel(buffer: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        // Start first recognition task
        beginRecognitionTask(recognizer: recognizer)
    }

    func startListening() throws {
        try startListening(for: "")
    }

    private func beginRecognitionTask(recognizer: SFSpeechRecognizer) {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        self.request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }

            if let transcript = result?.bestTranscription.formattedString {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Show: accumulated + current partial
                    let full = self.accumulatedTranscript.isEmpty
                        ? transcript
                        : self.accumulatedTranscript + " " + transcript
                    self.liveTranscript = full
                }
            }

            let didFinish = result?.isFinal == true || error != nil
            if didFinish {
                let finalText = result?.bestTranscription.formattedString ?? ""
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !finalText.isEmpty {
                        self.accumulatedTranscript = self.accumulatedTranscript.isEmpty
                            ? finalText
                            : self.accumulatedTranscript + " " + finalText
                        self.liveTranscript = self.accumulatedTranscript
                    }
                    // Restart recognition if still listening (handles ~60s server limit)
                    if self.isListening, let rec = self.recognizer {
                        self.task = nil
                        self.request = nil
                        // Small delay to avoid tight loop on repeated errors
                        if error != nil {
                            try? await Task.sleep(nanoseconds: 800_000_000)
                        }
                        if self.isListening {
                            self.beginRecognitionTask(recognizer: rec)
                        }
                    }
                }
            }
        }
    }

    @discardableResult
    func stopListening() -> URL? {
        guard isListening else { return nil }
        isListening = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        // Close file
        let recordedURL = currentRecordingURL
        audioFile = nil

        audioLevel = 0
        levelSampleCounter = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        // Keep liveTranscript and accumulatedTranscript for caller to read, then reset next start
        return recordedURL
    }

    // MARK: - Helpers

    private func makeAudioFileURL(projectId: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent(projectId.isEmpty ? "default" : projectId, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "")
        return dir.appendingPathComponent("\(name).caf")
    }

    private func processSampleLevel(buffer: AVAudioPCMBuffer) {
        levelSampleCounter += 1
        guard levelSampleCounter >= 4 else { return }  // ~10 fps at 1024 buffer / 44100hz
        levelSampleCounter = 0

        guard let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let frameLength = Int(buffer.frameLength)
        var sumSq: Float = 0
        for i in 0..<frameLength { sumSq += channelData[i] * channelData[i] }
        let rms = sqrt(sumSq / Float(frameLength))
        let normalized = min(rms * 20, 1.0)

        Task { @MainActor [weak self] in
            self?.audioLevel = normalized
        }
    }
}

extension AudioCaptureService: SpeechListeningService {
    var currentTranscript: String { liveTranscript }
    var liveTranscriptPublisher: AnyPublisher<String, Never> { $liveTranscript.eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { $audioLevel.eraseToAnyPublisher() }
}

struct PassthroughTranscriptionService: TranscriptionServicing {
    func finalizeTranscript(from rawTranscript: String) async throws -> String {
        rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribeAudioFile(at fileURL: URL) async throws -> String {
        if let transcript = try await recognizeAudioFile(at: fileURL) {
            return transcript
        }
        let data = try Data(contentsOf: fileURL)
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recognizeAudioFile(at fileURL: URL) async throws -> String? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: fileURL)
            request.shouldReportPartialResults = false

            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                if resumed { return }
                if let error {
                    resumed = true
                    continuation.resume(throwing: error)
                    return
                }
                if let result, result.isFinal {
                    resumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}

@MainActor
final class MockSpeechService: SpeechListeningService {
    private let subject = CurrentValueSubject<String, Never>("")
    private let levelSubject = CurrentValueSubject<Float, Never>(0)
    private let permissionGranted: Bool
    private let queuedTranscripts: [String]
    private var currentIndex = 0
    private(set) var startCallCount = 0

    init(
        permissionGranted: Bool = true,
        queuedTranscripts: [String] = ["We discussed the product roadmap and onboarding flow."]
    ) {
        self.permissionGranted = permissionGranted
        self.queuedTranscripts = queuedTranscripts.isEmpty ? [""] : queuedTranscripts
    }

    convenience init(launchConfiguration: AppLaunchConfiguration) {
        self.init(
            permissionGranted: launchConfiguration.microphonePermissionGranted,
            queuedTranscripts: launchConfiguration.queuedTranscripts
        )
    }

    var currentTranscript: String {
        subject.value
    }

    var liveTranscriptPublisher: AnyPublisher<String, Never> {
        subject.eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        levelSubject.eraseToAnyPublisher()
    }

    var currentRecordingURL: URL? { nil }

    func requestPermissions() async -> Bool {
        permissionGranted
    }

    func startListening(for projectId: String) throws {
        startCallCount += 1
        let transcript = queuedTranscripts[min(currentIndex, queuedTranscripts.count - 1)]
        currentIndex += 1
        subject.send(transcript)
    }

    func startListening() throws {
        try startListening(for: "")
    }

    @discardableResult
    func stopListening() -> URL? {
        return nil
    }

    func setTranscript(_ transcript: String) {
        subject.send(transcript)
    }
}

struct MockTranscriptionService: TranscriptionServicing {
    let transcriptOverride: String?
    let failureMessage: String?

    init(transcriptOverride: String? = nil, failureMessage: String? = nil) {
        self.transcriptOverride = transcriptOverride
        self.failureMessage = failureMessage
    }

    init(launchConfiguration: AppLaunchConfiguration) {
        transcriptOverride = nil
        failureMessage = launchConfiguration.transcriptionFailureMessage
    }

    func finalizeTranscript(from rawTranscript: String) async throws -> String {
        if let failureMessage {
            throw TestFailure.forced(failureMessage)
        }
        return (transcriptOverride ?? rawTranscript).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribeAudioFile(at fileURL: URL) async throws -> String {
        if let failureMessage {
            throw TestFailure.forced(failureMessage)
        }
        return (transcriptOverride ?? fileURL.deletingPathExtension().lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
