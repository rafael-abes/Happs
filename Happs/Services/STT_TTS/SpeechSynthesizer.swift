//
//  SpeechSynthesizer.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
import Foundation
import AVFoundation
import Combine

/// Text to speech with Apple's on-device synthesiser. One shared instance, so only
/// one thing is read aloud at a time. Tapping the same speaker again stops it.
@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechSynthesizer()

    /// ID of the item being read, so only its button shows the "stop" state.
    @Published private(set) var speakingID: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: ObjectIdentifier?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(id: String, text: String) {
        if speakingID == id {
            stop()
        } else {
            speak(id: id, text: text)
        }
    }

    func speak(id: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SpeechRecognizer.shared.stop()
        stop()

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        currentUtterance = ObjectIdentifier(utterance)
        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil   // stale delegate callbacks for the old utterance are now ignored
        speakingID = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Delegate (called off the main actor)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finished = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(finished) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let cancelled = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(cancelled) }
    }

    private func utteranceEnded(_ id: ObjectIdentifier) {
        guard currentUtterance == id else { return }
        currentUtterance = nil
        speakingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
