//
//  VoiceControls.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
// CODE OVERVIEW
// Reusable SwiftUI controls for voice: MicButton (speech to text), SpeakButton (text to speech)
// and VoiceSearchField (a search box with a mic). They are thin views over two shared singletons,
// SpeechRecognizer.shared and SpeechSynthesizer.shared, observed with @ObservedObject because the
// views do not own them. Because one recogniser is shared by the whole app, each control has an
// id string; the recogniser records which id owns the current recording so only that field
// receives the transcript. HappSpeechFixer is a pure, stateless helper kept separate so the
// text logic is easy to test without any UI.
import SwiftUI

/// Fixes the recogniser hearing "Happ" as "app". Only used where "app" is unlikely to be meant.
nonisolated enum HappSpeechFixer {
    /// Replaces the words "app" or "apps" with "Happ" or "Happs" (regex with word boundaries, so
    /// "apple" is untouched). The second pass turns "an Happ" into "a Happ", because the first
    /// pass would leave the wrong article behind ("an app" becomes "an Happ").
    static func fix(_ text: String) -> String {
        // Pass 1: swap the word. $1 keeps the optional plural s.
        var result = text.replacingOccurrences(
            of: #"\b[Aa]pp(s?)\b"#, with: "Happ$1", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\b([Aa])n\s+(Happs?)\b"#, with: "$1 $2", options: .regularExpression
        )
        return result
    }

    /// Adds dictated text to what was already in the field, with one space between,
    /// and applies the "Happ" fix only when asked.
    static func joined(base: String, transcript: String, fixesHapp: Bool) -> String {
        // Only fix the transcript, never the existing text, so earlier typing is not altered.
        let spoken = fixesHapp ? fix(transcript) : transcript
        // Add a space only if there is existing text that does not already end in one.
        let joiner = base.isEmpty || base.hasSuffix(" ") ? "" : " "
        return base + joiner + spoken
    }
}

/// Mic button that dictates into a text binding. `id` must be unique per field on screen.
/// Uses .borderless so it still works inside a Form row or tappable card.
struct MicButton: View {
    /// The field being dictated into. A binding, so the button writes straight back to the parent.
    @Binding var text: String
    /// Identifies this field to the shared recogniser, so two mic buttons never both react.
    let id: String
    /// Turn on for the assistant and search boxes. Leave off for free text like titles and notes.
    var fixesHapp = false
    /// Spoken by VoiceOver: "title" gives "Dictate title".
    var fieldName = "text"

    /// Shared app wide recogniser. @ObservedObject (not @StateObject) because this view does not own it.
    @ObservedObject private var recognizer = SpeechRecognizer.shared
    /// Text already in the field when dictation began. The transcript is appended to this, because
    /// the transcript is replaced into the field each update (assumed reason: the recogniser reports
    /// the whole transcript so far, so appending to a fixed base avoids repeating words).
    @State private var baseText = ""
    /// Drives the error alert.
    @State private var showAlert = false

    /// True only when recording AND this button is the owner, so other mic buttons stay idle.
    private var isActive: Bool {
        recognizer.isRecording && recognizer.activeOwnerID == id
    }

    var body: some View {
        Button {
            // Remember the current text only when starting, not when stopping.
            if !isActive { baseText = text }
            // toggle is async, so it is run in a Task from this synchronous button action.
            Task { await recognizer.toggle(ownerID: id) }
        } label: {
            Image(systemName: isActive ? "mic.fill" : "mic")
                .foregroundStyle(isActive ? Color.red : Color.happsGreenText)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Dictate \(fieldName)")
        .accessibilityValue(isActive ? "Listening" : "Not listening")
        .accessibilityHint("Double tap to start or stop. Your words are added to the field.")
        .onChange(of: recognizer.transcript) { _, newValue in
            // Ignore transcripts that belong to a different field, and empty ones.
            guard recognizer.transcriptOwnerID == id, !newValue.isEmpty else { return }
            text = HappSpeechFixer.joined(base: baseText, transcript: newValue, fixesHapp: fixesHapp)
        }
        .onChange(of: recognizer.errorMessage) { _, message in
            // Only the owning button shows the alert, otherwise every mic on screen would pop one.
            if message != nil && recognizer.errorOwnerID == id { showAlert = true }
        }
        .alert("Voice input", isPresented: $showAlert) {
            Button("OK") { recognizer.clearError() }
        } message: {
            Text(recognizer.errorMessage ?? "")
        }
    }
}

/// Speaker button that reads `text` aloud. Tap again to stop.
struct SpeakButton: View {
    /// Identifies this button, so the shared synthesizer knows which one is currently speaking.
    let id: String
    /// The sentence(s) to speak, usually a model's spokenSummary.
    let text: String
    /// What is being read, for VoiceOver: "Badminton" gives "Read Badminton aloud".
    var subject = ""

    /// Shared app wide synthesizer, observed so the icon updates when speech starts or stops.
    @ObservedObject private var synthesizer = SpeechSynthesizer.shared

    /// True when this button's id is the one being spoken.
    private var isSpeaking: Bool { synthesizer.speakingID == id }

    var body: some View {
        Button {
            // toggle starts speech, or stops it if this id is already speaking (tap again to stop).
            synthesizer.toggle(id: id, text: text)
        } label: {
            Image(systemName: isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                .foregroundStyle(Color.happsGreenText)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(subject.isEmpty ? "Read aloud" : "Read \(subject) aloud")
        .accessibilityValue(isSpeaking ? "Reading" : "")
        .accessibilityHint("Double tap to hear this read out. Double tap again to stop.")
    }
}

/// Search box with a mic, for the notifications inbox and the Happs map/list.
struct VoiceSearchField: View {
    /// Search string, owned by the parent screen so it can filter its list.
    @Binding var text: String
    /// Passed on to the MicButton as its unique owner id.
    let id: String
    var placeholder = "Search"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(placeholder)
            // The clear button only appears when there is something to clear.
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
            // fixesHapp is true here because searches often mention Happ (see HappSpeechFixer).
            MicButton(text: $text, id: id, fixesHapp: true, fieldName: "search")
        }
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
