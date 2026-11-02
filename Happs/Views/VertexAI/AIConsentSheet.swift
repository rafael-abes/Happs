//
//  AIConsentSheet.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


import SwiftUI

struct AIConsentSheet: View {
    let onAllow: () -> Void
    let onDecline: () -> Void

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

                    if let url = SupportInfo.privacyPolicyURL {
                        Link("Read the privacy policy", destination: url)
                            .frame(minHeight: 44)
                    }

                    VStack(spacing: 10) {
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
        .interactiveDismissDisabled()   // the person must choose, so consent is never implied
    }

    private func group(_ title: String, _ items: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: symbol)
                    .labelStyle(.titleAndIcon)
            }
        }
        .accessibilityElement(children: .contain)
    }
}