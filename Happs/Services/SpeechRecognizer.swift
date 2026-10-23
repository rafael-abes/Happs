//
//  SpeechRecognizer.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//

import Foundation
import Speech
import AVFoundation
import Combine
 
/// Box so the non-Sendable request can be used by the audio-thread tap.
nonisolated final class RecognitionRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}
 
/// Speech to text. One shared instance, so only one field can dictate at a time.
/// Audio and recogniser callbacks run off the main thread, so they are created in
/// nonisolated helpers and hop back to the main actor with plain values only.
@MainActor
final class SpeechRecognizer: ObservableObject {
    static let shared = SpeechRecognizer()
 
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    /// Which MicButton is (or was last) dictating. Kept after stopping so the final text still lands.
    @Published private(set) var transcriptOwnerID: String?
    @Published private(set) var activeOwnerID: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorOwnerID: String?
 
    private let maxSeconds = 60
    private var engine: AVAudioEngine?
    private var box: RecognitionRequestBox?
    private var task: SFSpeechRecognitionTask?
    private var sessionID = UUID()
    private var isStarting = false
    private var autoStop: Task<Void, Never>?
 
    private init() {}
 
    func toggle(ownerID: String) async {
        if isRecording && activeOwnerID == ownerID {
            stop()
        } else {
            await start(ownerID: ownerID)
        }
    }
 
    func start(ownerID: String) async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
 
        if isRecording { stop() }
        SpeechSynthesizer.shared.stop()
        clearError()
 
        guard await Self.requestPermissions() else {
            fail("Turn on Microphone and Speech Recognition for Happs in Settings.", owner: ownerID)
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-AU")), recognizer.isAvailable else {
            fail("Speech recognition isn't available right now.", owner: ownerID)
            return
        }
 
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
 
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Do not force on-device: if the en-AU model is not installed, recognition
            // fails instantly. Let iOS choose (on-device when ready, server otherwise).
            request.requiresOnDeviceRecognition = false
            let newBox = RecognitionRequestBox(request)
            let newEngine = AVAudioEngine()
            Self.installTap(on: newEngine, box: newBox)
            newEngine.prepare()
            try newEngine.start()
 
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
 
            autoStop = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.stopIfCurrent(id)
            }
        } catch {
            teardown()
            fail("Couldn't start the microphone.", owner: ownerID)
        }
    }
 
    func stop() {
        guard isRecording else { return }
        teardown()
    }
 
    func clearError() {
        errorMessage = nil
        errorOwnerID = nil
    }
 
    // MARK: Main-actor internals
 
    private func stopIfCurrent(_ id: UUID) {
        if sessionID == id { stop() }
    }
 
    fileprivate func handleResult(session: UUID, text: String?, isFinal: Bool, errorCode: Int?) {
        guard session == sessionID else { return }   // stale callback from an old session
        if let text { transcript = text }
        let failed = errorCode != nil
        if isFinal || failed {
            if failed && transcript.isEmpty {
                #if DEBUG
                print("Speech error code: \(errorCode ?? -1)")
                #endif
                if errorCode == 1110 {
                    fail("Didn't hear anything. Try again.", owner: activeOwnerID)
                } else {
                    fail("Voice input failed (code \(errorCode ?? -1)). Check Settings > Siri > Dictation is on and you are online.", owner: activeOwnerID)
                }
            }
            teardown()
        }
    }
 
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
 
    private func fail(_ message: String, owner: String?) {
        errorMessage = message
        errorOwnerID = owner
    }
 
    // MARK: Nonisolated helpers (run on audio and recogniser threads)
 
    nonisolated private static func requestPermissions() async -> Bool {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
 
    nonisolated private static func installTap(on engine: AVAudioEngine, box: RecognitionRequestBox) {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request.append(buffer)
        }
    }
 
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
