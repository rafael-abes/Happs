//
//  SpeechSynthesizer.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
// CODE OVERVIEW
// Text to speech built on AVSpeechSynthesizer, as a shared ObservableObject so speaker buttons can
// observe speakingID and show a stop state. It acts as the AVSpeechSynthesizerDelegate to learn
// when speech ends. Delegate callbacks come in off the main actor, so they are nonisolated and hop
// back with Task { @MainActor }. Utterance identity (ObjectIdentifier) is tracked so a finish
// callback from an old, cancelled utterance cannot clear the state of a new one.
//
import Foundation
import AVFoundation
import Combine

/// Text to speech with Apple's on-device synthesiser. One shared instance, so only
/// one thing is read aloud at a time. Tapping the same speaker again stops it.
@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    /// The one shared instance.
    static let shared = SpeechSynthesizer()

    /// ID of the item being read, so only its button shows the "stop" state.
    @Published private(set) var speakingID: String?

    /// Apple's on-device synthesiser.
    private let synthesizer = AVSpeechSynthesizer()
    /// Identity of the utterance we expect to finish; used to ignore stale delegate callbacks.
    private var currentUtterance: ObjectIdentifier?

    /// Private so only `shared` exists. override is needed because NSObject already has init().
    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaker button action: stop if this id is speaking, otherwise start speaking it.
    func toggle(id: String, text: String) {
        if speakingID == id {
            stop()
        } else {
            speak(id: id, text: text)
        }
    }

    /// Reads text aloud, first stopping any dictation and any earlier speech.
    func speak(id: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Free the microphone and audio session before we play.
        SpeechRecognizer.shared.stop()
        stop()

        // Playback category with spokenAudio mode; duckOthers lowers other audio while we talk.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        currentUtterance = ObjectIdentifier(utterance)
        speakingID = id
        synthesizer.speak(utterance)
    }

    /// Stops speaking, clears state and releases the audio session.
    func stop() {
        currentUtterance = nil   // stale delegate callbacks for the old utterance are now ignored
        speakingID = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Delegate (called off the main actor)

    // AVSpeechUtterance is not Sendable, so only its ObjectIdentifier is copied into the Task.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finished = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(finished) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let cancelled = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(cancelled) }
    }

    /// Resets state, but only if the finished utterance is the current one.
    private func utteranceEnded(_ id: ObjectIdentifier) {
        guard currentUtterance == id else { return }
        currentUtterance = nil
        speakingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
