//
//  AboutView.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//

// CODE OVERVIEW
// Static "About" screen pushed from the Me tab (ProfileView.isShowingAbout). It shows the app
// description, the developer details, the app version read from the bundle, and a list of
// acknowledgements (third-party libraries and services). It holds no shared state and talks to no
// store or service. The credits are plain data (an array of a private struct) rendered with
// ForEach, so adding a credit is one new array entry and no new view code. It can also present
// OnboardingView in a sheet so the welcome tour can be replayed.
//
import SwiftUI

/// One acknowledgement row. Private because only AboutView uses it. Identifiable (a fresh UUID per
/// instance) so ForEach can track rows; the UUID is not stable across launches, which is fine for a
/// static list.
private struct Credit: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    // nil means there is nothing to open (see the teaching-materials credit), so no Link is drawn.
    let url: URL?
}

/// The About screen. A List gives free scrolling, grouped sections and Dynamic Type support.
struct AboutView: View {
    /// Drives the sheet that replays the onboarding tour.
    @State private var showsTour = false

    /// Hard-coded acknowledgements. A constant array (not state) because it never changes at runtime.
    private let credits: [Credit] = [
        Credit(
            name: "Firebase iOS SDK",
            detail: "Authentication, Firestore, App Check and AI Logic. Google, Apache 2.0 licence.",
            url: URL(string: "https://github.com/firebase/firebase-ios-sdk")
        ),
        Credit(
            name: "Google Sign-In for iOS",
            detail: "Sign in with Google. Google, Apache 2.0 licence.",
            url: URL(string: "https://github.com/google/GoogleSignIn-iOS")
        ),
        Credit(
            name: "Gemini via Firebase AI Logic",
            detail: "Turns a typed or spoken sentence into a Happ draft.",
            url: URL(string: "https://firebase.google.com/docs/ai-logic")
        ),
        Credit(
            name: "Ticketmaster Discovery API",
            detail: "Event suggestions near campus.",
            url: URL(string: "https://developer.ticketmaster.com")
        ),
        Credit(
            name: "Apple frameworks",
            detail: "SwiftUI, MapKit, CoreLocation, Speech, AVFoundation, UserNotifications and Network.",
            url: URL(string: "https://developer.apple.com/documentation")
        ),
        Credit(
            name: "SF Symbols",
            detail: "System icons used across the app. Apple.",
            url: URL(string: "https://developer.apple.com/sf-symbols/")
        ),
        Credit(
            name: "Figma",
            detail: "Used to design the screens before building them.",
            url: URL(string: "https://www.figma.com")
        ),
        Credit(
            name: "FIT3178 teaching materials",
            detail: "Lab exercises and lecture content, Monash University.",
            url: nil
        ),
        Credit(
            name: "Supabase",
            detail: "Private photo storage for Happ recaps. supabase-swift, MIT licence.",
            url: URL(string: "https://github.com/supabase/supabase-swift")
        ),
    ]

    /// Marketing version and build number from Info.plist, for example "1.0 (1)". The fallbacks
    /// ("1.0" and "1") are used if a key is missing, so the label is never empty.
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // A List of sections: header, description, tour replay, developer details, credits.
    var body: some View {
        List {
            header

            Section("About Happs") {
                Text("Happs helps Monash students turn free time into plans. See which friends are on campus right now, post a spontaneous event called a Happ, and let people nearby join in one tap.")
                Text("The purpose is to make it easier to say yes to last-minute study sessions, meals and sport, while keeping you in control. Your location is only shared while you are on campus, only with your friends, and Invisible Mode hides you at any time.")
            }

            Section {
                Button {
                    showsTour = true
                } label: {
                    Label("Replay the welcome tour", systemImage: "questionmark.circle")
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Shows the welcome pages again.")
            }

            Section("Developer") {
                LabeledContent("Name", value: "Rafael Enrique Abes")
                LabeledContent("Student ID", value: "34122095")
            }

            Section {
                ForEach(credits) { credit in
                    creditRow(credit)
                }
            } header: {
                Text("Acknowledgments")
            } footer: {
                Text("Thank you to the authors and maintainers of the tools above. Happs was made for FIT3178 at Monash University, 2026.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsTour) {
            // OnboardingView takes a completion closure; here it just closes the sheet again.
            OnboardingView { showsTour = false }
        }
    }

    /// App icon, name and version. Wrapped in a Section so it sits inside the List, with the row
    /// background cleared so it looks like a title block rather than a table cell.
    private var header: some View {
        Section {
            VStack(spacing: 6) {
                Image(systemName: "figure.2.arms.open")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.happsGreenText)
                    .accessibilityHidden(true)
                Text("Happs")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Version \(versionText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    /// One credit row. Rows with a URL become a Link (opens in the browser); rows without one are
    /// plain text. @ViewBuilder lets the if/else return different view types.
    /// - Parameter credit: the credit to render.
    @ViewBuilder
    private func creditRow(_ credit: Credit) -> some View {
        if let url = credit.url {
            Link(destination: url) {
                creditText(credit)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(credit.name), \(credit.detail)")
            .accessibilityHint("Opens \(credit.name) in your browser.")
            .accessibilityAddTraits(.isLink)
        } else {
            creditText(credit)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(credit.name), \(credit.detail)")
        }
    }

    /// The shared visual content (name over detail) used by both the Link and plain variants.
    private func creditText(_ credit: Credit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(credit.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(credit.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(minHeight: 44, alignment: .leading)
    }
}


