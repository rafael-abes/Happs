//
//  PrivacySafetyView.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


import SwiftUI
import FirebaseAuth

struct PrivacySafetyView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var safetyStore: SafetyStore
    @State private var geminiOn = false

    var body: some View {
        List {
            Section("People") {
                NavigationLink {
                    BlockedUsersView()
                } label: {
                    HStack {
                        Text("Blocked people")
                        Spacer()
                        Text("\(safetyStore.blocked.count)").foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityHint("See and unblock people you blocked.")
            }

            Section {
                Toggle("Describe it (Google Gemini)", isOn: Binding(
                    get: { geminiOn },
                    set: { setGemini($0) }
                ))
                .accessibilityHint("When on, the sentence you type in Describe it is sent to Google Gemini to draft a Happ.")
            } header: {
                Text("AI")
            } footer: {
                Text("Turning this off stops Describe it from sending anything. You'll be asked again if you try to use it.")
            }

            Section("Help and policies") {
                if let url = SupportInfo.privacyPolicyURL { Link("Privacy policy", destination: url).frame(minHeight: 44) }
                if let url = SupportInfo.communityRulesURL { Link("Community rules", destination: url).frame(minHeight: 44) }
                if let url = SupportInfo.mailtoURL { Link("Contact support", destination: url).frame(minHeight: 44) }
            }

            Section {
                NavigationLink {
                    DeleteAccountView()
                } label: {
                    Text("Delete account")
                        .foregroundStyle(.red)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityHint("Permanently deletes your account and data.")
            }
        }
        .navigationTitle("Privacy and Safety")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
    }

    private func refresh() {
        guard let userID = authService.user?.uid else { return }
        geminiOn = AIConsent.hasConsented(userID: userID)
    }

    private func setGemini(_ on: Bool) {
        guard let userID = authService.user?.uid else { return }
        if on {
            AIConsent.setConsent(true, userID: userID)
        } else {
            AIConsent.setConsent(false, userID: userID)
        }
        geminiOn = on
    }
}
