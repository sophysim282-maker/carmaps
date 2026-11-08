import Foundation
import Speech
import AVFoundation

/// Mic button: speak a place name, it becomes the search text.
final class VoiceSearch: ObservableObject {
    @Published var listening = false
    @Published var text = ""
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(language: String, onFinal: @escaping (String) -> Void) {
        if listening { stop(); return }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { return }
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    DispatchQueue.main.async { if ok { self.begin(language, onFinal) } }
                }
            }
        }
    }

    private func begin(_ language: String, _ onFinal: @escaping (String) -> Void) {
        let locale = Locale(identifier: Settings.speechLocales[language] ?? "en-US")
        guard let rec = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), rec.isAvailable else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in
            req.append(buf)
        }
        engine.prepare()
        do { try engine.start() } catch { NavModel.voiceAudio(); return }
        request = req
        text = ""
        listening = true

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.listening else { return }
                if let result { self.text = result.bestTranscription.formattedString }
                if error != nil || (result?.isFinal ?? false) {
                    let t = self.text
                    self.stop()
                    if !t.isEmpty { onFinal(t) }
                }
            }
        }
        // Stop listening after 5 seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.listening == true { self?.request?.endAudio() }
        }
    }

    func stop() {
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        NavModel.voiceAudio()
    }
}
