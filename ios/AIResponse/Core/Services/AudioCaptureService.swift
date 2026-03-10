import AVFoundation
import Combine
import Speech

@MainActor
final class AudioCaptureService: ObservableObject {
    @Published var liveTranscript: String = ""

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

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
        liveTranscript = ""

        task?.cancel()
        task = nil

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        guard let request else { return }
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            if let transcript = result?.bestTranscription.formattedString {
                Task { @MainActor in
                    self?.liveTranscript = transcript
                }
            }

            if error != nil || result?.isFinal == true {
                self?.stopListening()
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        request?.endAudio()
        task?.cancel()

        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
    }
}
