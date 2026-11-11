//
//  AssistantSheet.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
//  generate() first checks AIConsent. Without consent it shows AIConsentSheet and sends nothing;
//  tapping Allow stores consent and continues, tapping Not now closes the sheet. The sentence is
//  also checked by ContentFilter before it is sent to Gemini.
//
import SwiftUI
import CoreLocation
import FirebaseAuth

/// "Describe it" sheet. The user types or dictates a sentence, reviews the draft,
/// and taps "Use this". The editor form is filled but nothing is saved.
struct AssistantSheet: View {
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var authService: AuthService
    @State private var showsConsent = false
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
            .sheet(isPresented: $showsConsent) {
                AIConsentSheet(
                    onAllow: {
                        if let userID = authService.user?.uid {
                            AIConsent.setConsent(true, userID: userID)
                        }
                        showsConsent = false
                        generate()
                    },
                    onDecline: { showsConsent = false }
                )
            }
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
            // CODE OVERVIEW
            // The "Describe it" feature UI. The person types or dictates one sentence; generate() sends it
            // through HappAssistant and HappIntentParser (which wrap AIService, the Firebase AI Logic /
            // Gemini client) and shows a draft for review. "Use this" hands the draft back to the editor
            // through the onApply closure, so nothing is saved here. The sheet is a small state machine:
            // the private Phase enum (idle, working, review, failed) drives which Form section is shown,
            // which is simpler and safer than several independent booleans. Dependencies arrive as
            // @EnvironmentObject so the sheet needs no initialiser arguments beyond onApply.
            //
            Button {
                generate()
            } label: {
                Label("Fill the form", systemImage: "sparkles")
                    .frame(minHeight: 44)
            }
                /// Gemini client wrapper, injected from the app root. Used to build the intent parser.
            .disabled(isWorking || sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                /// Source of the user's groups, so the model can suggest inviting one by name.
            .accessibilityHint("Sends only your sentence to Gemini and drafts the form.")
            /// Provides the campus region and boundary helpers (static members are used here).
        } header: {
                /// Supplies the signed-in user's uid, which keys the stored AI consent.
            Text("Say what you want to organise")
            /// True while AIConsentSheet is presented on top of this sheet.
        } footer: {
                /// Environment action that closes this sheet.
            Text("Example: pizza with the study crew tomorrow 6pm at the Campus Centre. Only this sentence is sent to Gemini.")
        }
    }

    private var workingSection: some View {
            /// The four screens of the flow. Each case carries only the data it needs (the result or the error text).
        Section {
            HStack {
                ProgressView()
                    .accessibilityHidden(true)
                Text("Thinking...")
                Spacer()
                Button("Cancel") {
                        /// The sentence being edited. @State because this view owns it; MicButton and TextEditor bind to it.
                    work?.cancel()
                        /// Current phase of the flow; changing it re-renders the Form.
                    phase = .idle
                    /// The in-flight generation task, kept so Close and Cancel can cancel it (cooperative cancellation).
                }
                .frame(minHeight: 44)
                    /// Form switching on phase. The switch inside Form is a ViewBuilder, so each case yields a section.
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
                            // Consent is presented as a nested sheet; Allow stores it and immediately resumes generate().
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
                                        // Stop the request and any dictation so nothing keeps running after dismissal.
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
        /// Text box with dictation button plus the "Fill the form" button (disabled when empty or busy).
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
            /// Spinner row with a Cancel button, shown while the request is running.
        // Guideline 5.1.2(i): nothing leaves the device until the person has said yes.
        guard let userID = authService.user?.uid, AIConsent.hasConsented(userID: userID) else {
            showsConsent = true
            return
        }
        let text = sentence
        if case .blocked = ContentFilter.check(text) {
            let message = "That sentence includes language that isn't allowed in Happs. Please reword it."
            phase = .failed(message)
            AccessibilityNotification.Announcement(message).post()
            return
        }
        phase = .working
        AccessibilityNotification.Announcement("Thinking.").post()
        work = Task {
            do {
                let assistant = HappAssistant(parser: HappIntentParser(generator: aiService))
                    /// Shows the parsed draft, any warnings from the assistant, and the "Use this" button.
                    /// Group is used so several Sections can be returned from one computed view.
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


