//
//  ReportSheet.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


// CODE OVERVIEW
// A form sheet used to report content or a person (photo, Happ, group, profile). The caller builds
// a ReportTarget describing what is reported and presents this sheet; the sheet gathers reason
// and details, then calls SafetyStore.report, which does the saving. Keeping the writing in the
// store (not the view) means the view only manages form state. Local @State tracks the form,
// sending and success so the same sheet can show either the form or a confirmation.
//
import SwiftUI
import FirebaseAuth

/// The report form. Shows a thank-you state after a successful send.
struct ReportSheet: View {
        /// What is being reported (kind, who, a summary and an optional id to hide it locally).
    let target: ReportTarget

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var safetyStore: SafetyStore
        // Closes the sheet; provided by SwiftUI so the view does not need to know how it was presented.
    @Environment(\.dismiss) private var dismiss

        // Form state. hideForMe defaults to true (see the SAFETY note above).
    @State private var reason: ReportReason = .harassment
    @State private var details = ""
    @State private var hideForMe = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isSent = false

        /// Maximum characters allowed in the details box.
    private let limit = 500

        // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                if isSent {
                    Section {
                        Label("Thanks. We'll review this report.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.happsGreenText)
                        Text("Reports are reviewed by a person. If someone is in danger, contact local emergency services.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("What are you reporting?") {
                        Text("\(target.kind.title.capitalized) by \(target.offenderName)")
                        if !target.summary.isEmpty {
                            Text(target.summary).font(.callout).foregroundStyle(.secondary)
                        }
                    }

                    Section("Reason") {
                        Picker("Reason", selection: $reason) {
                            ForEach(ReportReason.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        .accessibilityLabel("Reason for report")
                    }

                    Section {
                        TextField("Add details (optional)", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                                                        // Trims the text back to the limit as the user types or pastes.
                                                        // (The `_` ignores the old value; `new` is the updated text.)
                            .onChange(of: details) { _, new in
                                if new.count > limit { details = String(new.prefix(limit)) }
                            }
                        Text("\(details.count) of \(limit) characters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Details")
                    }

                                        // Only show the hide option when the target has an id that can be hidden.
                    if target.hideID != nil {
                        Section {
                            Toggle("Hide this for me", isOn: $hideForMe)
                        } footer: {
                            Text("You won't see it again. This doesn't tell the other person.")
                        }
                    }
                }
            }
            .navigationTitle(isSent ? "Report sent" : "Report \(target.kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSent ? "Done" : "Cancel") { dismiss() }
                }
                if !isSent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { send() }
                            .disabled(isSending)
                            .accessibilityValue(isSending ? "Sending" : "")
                            .accessibilityHint("Sends your report for review.")
                    }
                }
            }
            .alert("Couldn't Send Report", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

        /// Sends the report. Does nothing if no one is signed in. Runs async in a Task; `defer` always
        /// clears `isSending`, whether it succeeds or throws. The hide flag is only passed as true when
        /// the target supports hiding.
    private func send() {
        guard let userID = authService.user?.uid else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await safetyStore.report(
                    target, reason: reason, details: details,
                    reporterID: userID, hideForMe: hideForMe && target.hideID != nil
                )
                isSent = true
                AccessibilityNotification.Announcement("Report sent. Thank you.").post()
            } catch {
                errorMessage = "Your report didn't send. Check your connection and try again."
            }
        }
    }
}
