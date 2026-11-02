//
//  AssistantSheet.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
import SwiftUI
import CoreLocation

/// "Describe it" sheet. The user types or dictates a sentence, reviews the draft,
/// and taps "Use this". The editor form is filled but nothing is saved.
struct AssistantSheet: View {
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.dismiss) private var dismiss

    /// Called with the draft and the matched group's ID (if any).
    let onApply: (HappDraft, String?) -> Void

    private enum Phase {
        case idle
        case working
        case review(AssistantResult)
        case failed(String)
    }

    @State private var sentence = ""
    @State private var phase: Phase = .idle
    @State private var work: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                switch phase {
                case .idle:
                    EmptyView()
                case .working:
                    workingSection
                case .review(let result):
                    reviewSection(result)
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Describe it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        work?.cancel()
                        SpeechRecognizer.shared.stop()
                        dismiss()
                    }
                    .accessibilityHint("Closes without changing the form.")
                }
            }
        }
    }

    // MARK: Sections

    private var inputSection: some View {
        Section {
            HStack(alignment: .top) {
                TextEditor(text: $sentence)
                    .frame(minHeight: 100)
                    .accessibilityLabel("Describe your Happ")
                MicButton(text: $sentence, id: "assistant", fixesHapp: true, fieldName: "description")
            }
            Button {
                generate()
            } label: {
                Label("Fill the form", systemImage: "sparkles")
                    .frame(minHeight: 44)
            }
            .disabled(isWorking || sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityHint("Sends only your sentence to Gemini and drafts the form.")
        } header: {
            Text("Say what you want to organise")
        } footer: {
            Text("Example: pizza with the study crew tomorrow 6pm at the Campus Centre. Only this sentence is sent to Gemini.")
        }
    }

    private var workingSection: some View {
        Section {
            HStack {
                ProgressView()
                    .accessibilityHidden(true)
                Text("Thinking...")
                Spacer()
                Button("Cancel") {
                    work?.cancel()
                    phase = .idle
                }
                .frame(minHeight: 44)
                .accessibilityHint("Stops the request.")
            }
        }
    }

    private func reviewSection(_ result: AssistantResult) -> some View {
        Group {
            Section("Draft") {
                row("Title", result.draft.title)
                row("Category", result.draft.category.rawValue)
                row("Starts", result.draft.startTime.formatted(date: .abbreviated, time: .shortened))
                if let end = result.draft.endTime {
                    row("Ends", end.formatted(date: .abbreviated, time: .shortened))
                }
                if !result.draft.location.isEmpty {
                    row("Where", result.draft.location)
                }
                if let group = result.group {
                    row("Invite", group.name)
                }
            }
            if !result.warnings.isEmpty {
                Section("Please check") {
                    ForEach(result.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                    }
                }
            }
            Section {
                Button("Use this") {
                    onApply(result.draft, result.group?.id)
                    dismiss()
                }
                .frame(minHeight: 44)
                .accessibilityHint("Fills in the form with this draft. Nothing is saved yet.")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    private var groupCandidates: [GroupCandidate] {
        groupStore.groups.compactMap { group in
            let id: String? = group.id   // works whether id is String or String?
            guard let id else { return nil }
            return GroupCandidate(id: id, name: group.name)
        }
    }

    private func onCampus(_ coordinate: CLLocationCoordinate2D) -> Bool {
        LocationService.isInside(coordinate, polygon: LocationService.campusBoundary)
    }

    private func generate() {
        SpeechRecognizer.shared.stop()
        let text = sentence
        phase = .working
        AccessibilityNotification.Announcement("Thinking.").post()
        work = Task {
            do {
                let assistant = HappAssistant(parser: HappIntentParser(generator: aiService))
                let result = try await assistant.draft(
                    from: text,
                    groups: groupCandidates,
                    region: LocationService.campusRegion,
                    isOnCampus: { onCampus($0) }
                )
                if Task.isCancelled { return }
                phase = .review(result)
                AccessibilityNotification.Announcement("Draft ready. Review it below.").post()
            } catch {
                if Task.isCancelled { return }
                let message = AIError.classify(error).errorDescription ?? "Something went wrong."
                phase = .failed(message)
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }
}


