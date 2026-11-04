//
//  SpeechRecognizer.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//



// CODE OVERVIEW
// Speech to text for dictation buttons (MicButton views). It is one shared ObservableObject
// (singleton) so only one field can dictate at a time; ownerID strings tell each button whether
// the live transcript belongs to it. It uses Apple's SFSpeechRecognizer fed by an AVAudioEngine
// microphone tap. The audio tap and recogniser callbacks run on background threads, so they live
// in nonisolated static helpers and send plain values back to the main actor. A session UUID
// guards against late callbacks from a recording that has already been stopped. Recording
// is stopped automatically after 60 seconds.
//
import Foundation
import Speech
import AVFoundation
import Combine
 
/// Box so the non-Sendable request can be used by the audio-thread tap.
// @unchecked Sendable is a promise to the compiler that this is safe: the request is created once
// and only used for appending audio from the tap and ending audio at teardown.
// (assumed reason: SFSpeechAudioBufferRecognitionRequest is not marked Sendable)
nonisolated final class RecognitionRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}
 
/// Speech to text. One shared instance, so only one field can dictate at a time.
/// Audio and recogniser callbacks run off the main thread, so they are created in
/// nonisolated helpers and hop back to the main actor with plain values only.
@MainActor
final class SpeechRecognizer: ObservableObject {
    /// The one shared instance; callers use `SpeechRecognizer.shared` (the initialiser is private).
    static let shared = SpeechRecognizer()
 
    /// True while the microphone is live.
    @Published private(set) var isRecording = false
    /// Latest (partial or final) recognised text.
    @Published private(set) var transcript = ""
    /// Which MicButton is (or was last) dictating. Kept after stopping so the final text still lands.
    @Published private(set) var transcriptOwnerID: String?
    /// Owner of the recording that is running now; nil when idle.
    @Published private(set) var activeOwnerID: String?
    /// Message to show the user, with errorOwnerID saying which button should display it.
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorOwnerID: String?
 
    /// Words the recogniser should expect. Stops "Happ" being heard as "app".
    nonisolated static let contextualStrings = [
        "Happ", "Happs", "a Happ", "Monash", "Matheson Library", "Campus Centre"
    ]
 
    /// Intended recording limit in seconds. (The auto stop task below currently uses the literal 60.)
    private let maxSeconds = 60
    /// Audio engine that owns the microphone input.
    private var engine: AVAudioEngine?
    /// The request currently receiving audio.
    private var box: RecognitionRequestBox?
    /// The running recognition task, cancelled on teardown.
    private var task: SFSpeechRecognitionTask?
    /// Changes for every recording; callbacks carrying an old id are ignored.
    private var sessionID = UUID()
    /// Re-entrancy guard: start is async (permissions), so a double tap must not start two sessions.
    private var isStarting = false
    /// Timer task that ends a recording after the time limit.
    private var autoStop: Task<Void, Never>?
 
    private init() {}
 
    /// Mic button action: stops if this owner is recording, otherwise starts (stopping any other owner first).
    func toggle(ownerID: String) async {
        if isRecording && activeOwnerID == ownerID {
            stop()
        } else {
            await start(ownerID: ownerID)
        }
    }
 
    /// Requests permission, configures the audio session, wires the mic to a recognition request and starts it.
    func start(ownerID: String) async {
        guard !isStarting else { return }
        isStarting = true
        // defer runs on every exit path, including the early returns below.
        defer { isStarting = false }
 
        if isRecording { stop() }
        // Silence text to speech so the microphone does not hear it.
        SpeechSynthesizer.shared.stop()
        clearError()
 
        guard await Self.requestPermissions() else {
            fail("Turn on Microphone and Speech Recognition for Happs in Settings.", owner: ownerID)
            return
        }
        // en-AU matches the app's Australian campus users.
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-AU")), recognizer.isAvailable else {
            fail("Speech recognition isn't available right now.", owner: ownerID)
            return
        }
 
        do {
            let session = AVAudioSession.sharedInstance()
            // Record category with measurement mode (minimal system audio processing); duckOthers lowers other apps' audio.
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
 
            let request = SFSpeechAudioBufferRecognitionRequest()
            // Partial results let the text appear live while the user is still speaking.
            request.shouldReportPartialResults = true
            // Do not force on-device: if the en-AU model is not installed, recognition
            // fails instantly. Let iOS choose (on-device when ready, server otherwise).
            request.requiresOnDeviceRecognition = false
            // Hints so "Happ" is not heard as "app". Helps, but is not a guarantee.
            request.contextualStrings = Self.contextualStrings
            let newBox = RecognitionRequestBox(request)
            let newEngine = AVAudioEngine()
            // Tap installed before the engine starts, so no audio is missed.
            Self.installTap(on: newEngine, box: newBox)
            newEngine.prepare()
            try newEngine.start()
 
            // New session id; stored so stale callbacks can be recognised.
            let id = UUID()
            sessionID = id
            engine = newEngine
            box = newBox
            task = Self.startTask(
                recognizer: recognizer,
                box: newBox,
                handler: Self.makeHandler(owner: self, session: id)
            )
            transcript = ""
            transcriptOwnerID = ownerID
            activeOwnerID = ownerID
            isRecording = true
 
            // [weak self] so this sleeping task does not keep the recogniser alive; it ends the session only if it is still the current one.
            autoStop = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.stopIfCurrent(id)
            }
        } catch {
            // Release everything if setup failed halfway.
            teardown()
            fail("Couldn't start the microphone.", owner: ownerID)
        }
    }
 
    /// Stops recording. The recogniser may still deliver a final result, which handleResult accepts if the session is still current. (assumed: teardown cancels the task, so late results are dropped)
    func stop() {
        guard isRecording else { return }
        teardown()
    }
 
    /// Clears the error so the UI hides it.
    func clearError() {
        errorMessage = nil
        errorOwnerID = nil
    }
 
    // MARK: Main-actor internals
 
    private func stopIfCurrent(_ id: UUID) {
        if sessionID == id { stop() }
    }
 
    /// Runs on the main actor for each recogniser callback. Updates the transcript, and tears down when the result is final or an error arrives.
    fileprivate func handleResult(session: UUID, text: String?, isFinal: Bool, errorCode: Int?) {
        guard session == sessionID else { return }   // stale callback from an old session
        if let text { transcript = text }
        let failed = errorCode != nil
        if isFinal || failed {
            if failed && transcript.isEmpty {
                #if DEBUG
                print("Speech error code: \(errorCode ?? -1)")
                #endif
                // 1110 is the code treated here as "no speech detected" (assumed from the message shown).
                if errorCode == 1110 {
                    fail("Didn't hear anything. Try again.", owner: activeOwnerID)
                } else {
                    fail("Voice input failed (code \(errorCode ?? -1)). Check Settings > Siri > Dictation is on and you are online.", owner: activeOwnerID)
                }
            }
            teardown()
        }
    }
 
    /// Stops the engine, removes the mic tap, ends audio, cancels the task and resets state. Safe to call more than once.
    private func teardown() {
        autoStop?.cancel()
        autoStop = nil
        sessionID = UUID()   // any late callback now fails the session check
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        box?.request.endAudio()
        task?.cancel()
        engine = nil
        box = nil
        task = nil
        isRecording = false
        activeOwnerID = nil
        // Release the audio session and tell other apps they may resume their audio.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
 
    /// Records an error for a given owner.
    private func fail(_ message: String, owner: String?) {
        errorMessage = message
        errorOwnerID = owner
    }
 
    // MARK: Nonisolated helpers (run on audio and recogniser threads)
 
    /// Asks for speech recognition and microphone permission in turn. True only if both are granted.
    nonisolated private static func requestPermissions() async -> Bool {
        // Bridges the old callback style requestAuthorization into async/await.
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
 
    /// Feeds microphone buffers into the recognition request. The closure runs on the audio thread, which is why it only touches the Sendable box.
    nonisolated private static func installTap(on engine: AVAudioEngine, box: RecognitionRequestBox) {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request.append(buffer)
        }
    }
 
    /// Starts the recognition task and converts its result/error into plain values for the handler.
    nonisolated private static func startTask(
        recognizer: SFSpeechRecognizer,
        box: RecognitionRequestBox,
        handler: @escaping @Sendable (String?, Bool, Int?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: box.request) { result, error in
            let code = error.map { ($0 as NSError).code }
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, code)
        }
    }
 
    /// Builds a Sendable closure that hops to the main actor and calls handleResult, passing the session id.
    nonisolated private static func makeHandler(
        owner: SpeechRecognizer,
        session: UUID
    ) -> @Sendable (String?, Bool, Int?) -> Void {
        return { text, isFinal, errorCode in
            Task { @MainActor in
                owner.handleResult(session: session, text: text, isFinal: isFinal, errorCode: errorCode)
            }
        }
    }
}
