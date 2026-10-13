import AVFoundation
import Speech

/// Push-to-talk: tap the microphone, speak, tap again (or pause) and the text is delivered once.
/// Recognition runs on the iPhone's own speech service; Kimi stops listening while it speaks.
@MainActor
final class Voice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var listening = false
    @Published private(set) var heard = ""
    @Published private(set) var note: String?   // why listening could not start
    @Published private(set) var speaking = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onText: ((String) -> Void)?
    private var player: AVAudioPlayer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(onText: @escaping (String) -> Void) {
        if listening { finish() } else { Task { await start(onText: onText) } }
    }

    private func start(onText: @escaping (String) -> Void) async {
        guard await Self.permitted() else {
            note = "Нет доступа к микрофону или распознаванию речи: разрешите их в Настройках → Kimy."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            note = "Распознавание речи сейчас недоступно."
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        self.onText = onText
        heard = ""
        note = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.heard = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.finish() }
                }
            }
            listening = true
        } catch {
            note = "Не удалось включить микрофон: \(error.localizedDescription)"
            stopEngine()
        }
    }

    /// Ends listening and hands over what was heard exactly once.
    private func finish() {
        guard listening else { return }
        listening = false
        stopEngine()
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let deliver = onText
        onText = nil
        if !text.isEmpty { deliver?(text) }
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        synthesizer.speak(utterance)
    }

    /// A personal SpeechKit voice when its key is set; the iPhone's own voice otherwise or if SpeechKit fails.
    func say(_ text: String, as voice: SpeechKit.Voice) {
        let key = Keychain.read(Keychain.speechkit)
        guard !key.isEmpty, let request = try? SpeechKit.request(text, voice: voice, key: key) else { say(SpeechKit.speakable(text)); return }
        hush()
        speaking = true
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let audio = SpeechKit.audio(data)
                guard (response as? HTTPURLResponse)?.statusCode == 200, !audio.isEmpty else { throw KimiCore.Failure.emptyReply }
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                player = try AVAudioPlayer(data: audio)
                player?.delegate = self
                player?.play()
            } catch {
                speaking = false
                say(SpeechKit.speakable(text))
            }
        }
    }

    func hush() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        speaking = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.speaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = synthesizer.isSpeaking }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }

    private static func permitted() async -> Bool {
        let speech = await withCheckedContinuation { done in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        let mic = await withCheckedContinuation { done in
            AVAudioSession.sharedInstance().requestRecordPermission { done.resume(returning: $0) }
        }
        return speech && mic
    }
}
