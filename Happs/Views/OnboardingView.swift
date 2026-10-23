//
//  OnboardingView.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
import SwiftUI
 
private struct OnboardingPage: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let message: String
    let tips: [String]
 
    static let all: [OnboardingPage] = [
        OnboardingPage(
            symbol: "figure.2.arms.open",
            title: "Welcome to Happs",
            message: "Turn free time on campus into spontaneous plans with your friends.",
            tips: [
                "See who is around right now",
                "Post a Happ and let people join in one tap",
                "Everything is built for Monash campus life"
            ]
        ),
        OnboardingPage(
            symbol: "map.fill",
            title: "Find your friends",
            message: "Add friends in the Friends tab and see them on the campus map.",
            tips: [
                "Search by name, then send a request",
                "Pins show while you are both on campus and visible",
                "Set your status on the Me tab: Available, In Class, Busy or Do Not Disturb"
            ]
        ),
        OnboardingPage(
            symbol: "plus.circle.fill",
            title: "Create a Happ",
            message: "A Happ is a spontaneous event: a study session, a meal, a kick-around.",
            tips: [
                "Open the Happs tab and tap +",
                "Pick a place, time and category",
                "Start from a Ticketmaster event near campus",
                "Tap a Happ on the map or list to join or leave"
            ]
        ),
        OnboardingPage(
            symbol: "person.3.fill",
            title: "Use groups",
            message: "Make a group of friends and invite them all to a Happ at once.",
            tips: [
                "Create a group from the Friends tab",
                "Members accept the invite to join",
                "Choose a group when you create a Happ"
            ]
        ),
        OnboardingPage(
            symbol: "sparkles",
            title: "Talk to Happs",
            message: "Describe a plan in a sentence and let the assistant fill the form for you.",
            tips: [
                "In New Happ, tap Describe it and type or dictate",
                "Review the draft, then tap Use this",
                "Use the mic to dictate or search, and the speaker to hear a Happ read aloud"
            ]
        ),
        OnboardingPage(
            symbol: "bell.badge.fill",
            title: "Stay in control",
            message: "You choose who sees you, and you never miss an invite.",
            tips: [
                "Your location is only shared while you are on campus",
                "Only friends can see it, and Invisible Mode hides you any time",
                "Invites and Happ updates land in your notifications on the Me tab"
            ]
        )
    ]
}
 
/// Remembers, per account, whether the welcome tour has been shown.
enum OnboardingStore {
    private static func key(_ userID: String) -> String { "hasSeenOnboarding.\(userID)" }
 
    static func hasSeen(_ userID: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(userID))
    }
 
    static func markSeen(_ userID: String, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(userID))
    }
}
 
struct OnboardingView: View {
    let onFinish: () -> Void
 
    @State private var page = 0
    @ScaledMetric private var iconSize = 84.0
    private let pages = OnboardingPage.all
 
    private var isLast: Bool { page == pages.count - 1 }
 
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
            }
            .padding(.horizontal)
 
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                    pageView(item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
 
            pageDots
                .padding(.vertical, 12)
 
            Button {
                if isLast {
                    onFinish()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(isLast ? "Get started" : "Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.happsGreen, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }
 
    private func pageView(_ item: OnboardingPage) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: item.symbol)
                    .font(.system(size: iconSize))
                    .foregroundStyle(Color.happsGreen)
                    .padding(.top, 24)
                    .accessibilityHidden(true)
 
                Text(item.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
 
                Text(item.message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
 
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(item.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.happsGreen)
                            Text(tip)
                                .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
        }
    }
 
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.happsGreen : Color(.tertiaryLabel))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(pages.count)")
    }
}
 
/// Shows the tour once per account, the first time that account reaches the main app.
private struct OnboardingGate: ViewModifier {
    let userID: String?
    @State private var isShowing = false
 
    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isShowing) {
                OnboardingView {
                    if let userID { OnboardingStore.markSeen(userID) }
                    isShowing = false
                }
                .interactiveDismissDisabled()
            }
            .onChange(of: userID, initial: true) { _, newID in
                if let newID, !OnboardingStore.hasSeen(newID) {
                    isShowing = true
                }
            }
    }
}
 
extension View {
    func onboarding(for userID: String?) -> some View {
        modifier(OnboardingGate(userID: userID))
    }
}
