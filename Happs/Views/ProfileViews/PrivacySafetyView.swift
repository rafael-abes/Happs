//
//  PrivacySafetyView.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


// CODE OVERVIEW
// A settings-style hub pushed from the Me tab (ProfileView). It links to the blocked list and the
// delete-account flow, shows the blocked count from SafetyStore, links to the published policy and
// support URLs held in SupportInfo, and hosts the Gemini consent switch. Consent is not stored in
// Firestore: AIConsent reads and writes a per-user UserDefaults key, so this view mirrors that value
// into a local @State and writes changes straight back.
//
import SwiftUI

/// Privacy, safety and account links in one List.
struct PrivacySafetyView: View {
    // Injected shared objects: the signed-in user (for the consent key) and the blocked list.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var safetyStore: SafetyStore
    /// Local copy of the stored consent so the Toggle can display it. Refreshed in onAppear.
    @State private var geminiOn = false

    // Sections: People, AI consent, policy links, destructive account deletion (kept last and red).
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
                // Custom Binding instead of $geminiOn so that flipping the switch also persists the choice via setGemini.
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
                // SupportInfo URLs are optional, so each Link is only drawn when its URL exists.
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
        // Re-read the stored consent each time the screen appears, in case it changed elsewhere (e.g. the consent sheet).
        .onAppear { refresh() }
    }

    /// Loads the saved consent for the current user into geminiOn. No user means nothing to load.
    private func refresh() {
        guard let userID = authService.user?.uid else { return }
        geminiOn = AIConsent.hasConsented(userID: userID)
    }

    /// Saves the consent choice for the current user and updates the switch.
    /// - Parameter on: true to grant consent, false to withdraw it (the stored key is removed).
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



