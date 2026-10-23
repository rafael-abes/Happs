//
//  VoiceControls.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
import SwiftUI

/// Mic button that dictates into a text binding. `id` must be unique per field on screen.
/// Uses .borderless so it still works inside a Form row or tappable card.
struct MicButton: View {
    @Binding var text: String
    let id: String

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
                .foregroundStyle(isActive ? Color.red : Color.happsGreen)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isActive ? "Stop dictation" : "Start dictation")
        .onChange(of: recognizer.transcript) { _, newValue in
            guard recognizer.transcriptOwnerID == id, !newValue.isEmpty else { return }
            let joiner = baseText.isEmpty || baseText.hasSuffix(" ") ? "" : " "
            text = baseText + joiner + newValue
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

    @ObservedObject private var synthesizer = SpeechSynthesizer.shared

    private var isSpeaking: Bool { synthesizer.speakingID == id }

    var body: some View {
        Button {
            synthesizer.toggle(id: id, text: text)
        } label: {
            Image(systemName: isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                .foregroundStyle(Color.happsGreen)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isSpeaking ? "Stop reading aloud" : "Read aloud")
    }
}

/// Search box with a mic, for the notifications inbox and the Happs map/list.
struct VoiceSearchField: View {
    @Binding var text: String
    let id: String
    var placeholder = "Search"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
            MicButton(text: $text, id: id)
        }
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

