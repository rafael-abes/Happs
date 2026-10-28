//
//  AboutView.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//

import SwiftUI
 
private struct Credit: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let url: URL?
}
 
struct AboutView: View {
    @State private var showsTour = false
 
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
 
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
 
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
                }
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
            OnboardingView { showsTour = false }
        }
    }
 
    private var header: some View {
        Section {
            VStack(spacing: 6) {
                Image(systemName: "figure.2.arms.open")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.happsGreen)
                    .accessibilityHidden(true)
                Text("Happs")
                    .font(.largeTitle.bold())
                Text("Version \(versionText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
 
    @ViewBuilder
    private func creditRow(_ credit: Credit) -> some View {
        if let url = credit.url {
            Link(destination: url) {
                creditText(credit)
            }
        } else {
            creditText(credit)
        }
    }
 
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
    }
}
