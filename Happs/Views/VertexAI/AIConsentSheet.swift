//
//  AIConsentSheet.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


// CODE OVERVIEW
// A modal consent screen (View layer) shown before any text is sent to Google Gemini. It is
// "dumb" on purpose: it holds no consent state and does not write to storage. The parent
// (AssistantSheet) passes two closures, onAllow and onDecline, and decides what to do, which
// keeps the legal copy separate from the logic and makes the view easy to reuse or preview.
// The bullet text comes from the AIConsent type (AIConsent.whatIsSent / whatIsNotSent), so the
// wording shown here and the versioned consent record share one source of truth.
//
import SwiftUI

/// Full-screen explanation of what "Describe it" sends to Gemini, with Allow and Not now buttons.
/// Presented as a sheet by AssistantSheet; it only reports the choice through closures.
struct AIConsentSheet: View {
        /// Called when the person taps Allow. The parent stores consent and continues generating.
    let onAllow: () -> Void
        /// Called when the person taps Not now. The parent closes the sheet and sends nothing.
    let onDecline: () -> Void

        /// Heading, plain-language disclosure, the two lists, the privacy policy link and the buttons,
        /// all inside a ScrollView so large Dynamic Type sizes remain reachable.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(Color.happsGreenText)
                        .accessibilityHidden(true)

                    Text("Describe it uses Google Gemini")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)

                    Text("To turn your sentence into a draft Happ, Happs sends it to Google's Gemini AI service. Google processes it to write the draft. You always review the draft before anything is saved.")

                    group("What is sent", AIConsent.whatIsSent, symbol: "arrow.up.circle")
                    group("What is not sent", AIConsent.whatIsNotSent, symbol: "xmark.circle")

                    Text("You can change your mind any time in Me > Privacy and Safety. If you choose Not now, the rest of Happs works as normal and you can still fill the form in yourself.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                                        // SupportInfo.privacyPolicyURL is optional, so the link only appears when a URL exists.
                    if let url = SupportInfo.privacyPolicyURL {
                        Link("Read the privacy policy", destination: url)
                            .frame(minHeight: 44)
                    }

                    VStack(spacing: 10) {
                                                // Button(action:) takes the stored closure directly; the two buttons are
                                                // visually equal (prominent vs bordered) so declining is not discouraged.
                        Button(action: onAllow) {
                            Text("Allow").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Lets Happs send your sentence to Google Gemini for Describe it.")

                        Button(action: onDecline) {
                            Text("Not now").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Nothing is sent. Describe it stays off.")
                    }
                    .controlSize(.large)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
                // (assumed reason for interactiveDismissDisabled: swiping the sheet away would otherwise
                // count as a silent decision, so the only exits are the two buttons.)
        .interactiveDismissDisabled()   // the person must choose, so consent is never implied
    }

        /// Builds one titled list of disclosure items (used for "What is sent" and "What is not sent").
        /// - Parameters:
        ///   - title: Section heading, marked as a header for VoiceOver.
        ///   - items: One line per disclosed item.
        ///   - symbol: SF Symbol shown beside each line so the meaning is not conveyed by words alone.
    private func group(_ title: String, _ items: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                        // id: \.self works because the items are unique strings, so no wrapper model is needed.
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: symbol)
                    .labelStyle(.titleAndIcon)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
