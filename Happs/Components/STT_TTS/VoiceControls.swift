//
//  VoiceControls.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
import SwiftUI

/// Fixes the recogniser hearing "Happ" as "app". Only used where "app" is unlikely to be meant.
nonisolated enum HappSpeechFixer {
    static func fix(_ text: String) -> String {
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
        let spoken = fixesHapp ? fix(transcript) : transcript
        let joiner = base.isEmpty || base.hasSuffix(" ") ? "" : " "
        return base + joiner + spoken
    }
}

/// Mic button that dictates into a text binding. `id` must be unique per field on screen.
/// Uses .borderless so it still works inside a Form row or tappable card.
struct MicButton: View {
    @Binding var text: String
    let id: String
    /// Turn on for the assistant and search boxes. Leave off for free text like titles and notes.
    var fixesHapp = false
    /// Spoken by VoiceOver: "title" gives "Dictate title".
    var fieldName = "text"

    @ObservedObject private var recognizer = SpeechRecognizer.shared
    @State private var baseText = ""
    @State private var showAlert = false

    private var isActive: Bool {
        recognizer.isRecording && recognizer.activeOwnerID == id
    }

    var body: some View {
        Button {
            if !isActive { baseText = text }
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
            guard recognizer.transcriptOwnerID == id, !newValue.isEmpty else { return }
            text = HappSpeechFixer.joined(base: baseText, transcript: newValue, fixesHapp: fixesHapp)
        }
        .onChange(of: recognizer.errorMessage) { _, message in
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
    let id: String
    let text: String
    /// What is being read, for VoiceOver: "Badminton" gives "Read Badminton aloud".
    var subject = ""

    @ObservedObject private var synthesizer = SpeechSynthesizer.shared

    private var isSpeaking: Bool { synthesizer.speakingID == id }

    var body: some View {
        Button {
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
    @Binding var text: String
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
            MicButton(text: $text, id: id, fixesHapp: true, fieldName: "search")
        }
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
