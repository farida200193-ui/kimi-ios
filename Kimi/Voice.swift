import AVFoundation
import Speech

/// Voice conversation: tap once, talk; a pause ends the phrase, Kimy answers aloud and listens again.
/// «Стоп», a tap or 8 seconds of silence end the conversation. Recognition runs on the iPhone; Kimy doesn't listen while it speaks.
@MainActor
final class Voice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var listening = false
    @Published private(set) var heard = ""
    @Published private(set) var note: String?   // why listening could not start
    @Published private(set) var speaking = false
    @Published private(set) var conversation = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onText: ((String) -> Void)?
    private var player: AVAudioPlayer?
    private var handler: ((String) -> Void)?    // kept for the next turn of the conversation
    private var silence: Task<Void, Never>?
    private static let pause: UInt64 = 1_400_000_000      // end of a phrase
    private static let quiet: UInt64 = 8_000_000_000      // nobody speaks: the conversation ends

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(onText: @escaping (String) -> Void) {
        if listening { finish() } else { Task { await start(onText: onText) } }
    }

    /// Starts the hands-free conversation, or ends it if it is on.
    func converse(onText: @escaping (String) -> Void) {
        if conversation || listening { endConversation(); return }
        conversation = true
        handler = onText
        Task { await start(onText: onText) }
    }

    func endConversation() {
        conversation = false
        handler = nil
        silence?.cancel()
        if listening { listening = false; onText = nil; stopEngine() }
        hush()
    }

    /// The next turn: after Kimy has spoken, or when there was nothing to say.
    func listenAgain() {
        guard conversation, !listening, !speaking, let handler = handler else { return }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)   // let the speaker fall silent before the mic opens
            if conversation, !listening, !speaking { await start(onText: handler) }
        }
    }

    private func waitForSilence() {
        silence?.cancel()
        let heardSomething = !heard.isEmpty
        silence = Task {
            try? await Task.sleep(nanoseconds: heardSomething ? Self.pause : Self.quiet)
            guard !Task.isCancelled, listening else { return }
            if heardSomething { finish() } else if conversation { endConversation() } else { finish() }
        }
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
                    if let result, result.bestTranscription.formattedString != self.heard {
                        self.heard = result.bestTranscription.formattedString
                        self.waitForSilence()
                    }
                    if error != nil || result?.isFinal == true { self.finish() }
                }
            }
            listening = true
            waitForSilence()
        } catch {
            note = "Не удалось включить микрофон: \(error.localizedDescription)"
            stopEngine()
        }
    }

    /// Ends listening and hands over what was heard exactly once.
    private func finish() {
        guard listening else { return }
        listening = false
        silence?.cancel()
        stopEngine()
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let deliver = onText
        onText = nil
        if conversation && KimiCore.endsConversation(text) { endConversation(); say("Хорошо, до связи!"); return }
        if !text.isEmpty { deliver?(text) } else { listenAgain() }
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
        Task { @MainActor in self.speaking = false; self.listenAgain() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speaking = synthesizer.isSpeaking
            if !self.speaking { self.listenAgain() }
        }
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
