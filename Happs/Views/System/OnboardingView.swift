//
//  OnboardingView.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
// CODE OVERVIEW
// First-run welcome tour. OnboardingPage is the data (an array of static content), OnboardingView draws a
// paged TabView with dots, Skip and Next, and OnboardingStore remembers in UserDefaults that an account has
// seen it. The key includes the user ID, so each account sees the tour once even on a shared phone.
// OnboardingGate is a ViewModifier applied through .onboarding(for:), which shows the tour in a full
// screen cover the first time a signed-in user reaches the main app.
import SwiftUI

/// Content of one tour page. Private to this file. Identifiable so ForEach can loop over it.
private struct OnboardingPage: Identifiable {
    // A new random id per instance, only for SwiftUI identity (not stored anywhere).
    let id = UUID()
    /// SF Symbol name for the page icon.
    let symbol: String
    let title: String
    let message: String
    /// Bullet points shown in the card.
    let tips: [String]

    /// The six pages in order. Static data so the view needs no setup.
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
/// Namespace (a caseless enum cannot be instantiated) for the UserDefaults helpers.
enum OnboardingStore {
    // One flag per account.
    private static func key(_ userID: String) -> String { "hasSeenOnboarding.\(userID)" }

    /// The defaults parameter lets tests pass in a throwaway UserDefaults instead of the real one.
    static func hasSeen(_ userID: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(userID))
    }

    static func markSeen(_ userID: String, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(userID))
    }
}

/// The tour screen.
struct OnboardingView: View {
    /// Called when the user taps Skip or Get started. The caller decides what finishing means.
    let onFinish: () -> Void

    // Index of the current page, bound to the TabView selection and read by the dots.
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var iconSize = 84.0
    // Copied once so the view does not repeat the static lookup.
    private let pages = OnboardingPage.all

    private var isLast: Bool { page == pages.count - 1 }

    // Layout from top to bottom: Skip, paged content, page dots, main button.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Skip the tour")
                    .accessibilityHint("Goes straight to the app.")
                    .frame(minWidth: 44, minHeight: 44)
                    // Skip is hidden and disabled on the last page but still takes space, so the layout does not jump.
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
            }
            .padding(.horizontal)

            // A TabView in page style gives swipeable pages. Each page's .tag(index) matches the selection value.
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                    pageView(item).tag(index)
                }
            }
 .tabViewStyle(.page(indexDisplayMode: .never))
            // Fires on swipe, button or dots, so the VoiceOver announcement covers all of them.
            .onChange(of: page) { _, newPage in
                AccessibilityNotification.Announcement(
                    "Page \(newPage + 1) of \(pages.count), \(pages[newPage].title)"
                ).post()
            }

            pageDots
                .padding(.vertical, 12)

            Button {
                if isLast {
                    onFinish()
                } else {
                    // Same change either way, animated only when Reduce Motion is off.
                    if reduceMotion { page += 1 } else { withAnimation { page += 1 } }
                }
            } label: {
                Text(isLast ? "Get started" : "Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.happsGreenFill, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            .accessibilityHint(isLast ? "Finishes the tour and opens the app." : "Goes to the next page.")
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }

    /// Builds one page: icon, title, message and the tips card.
    private func pageView(_ item: OnboardingPage) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: item.symbol)
                    .font(.system(size: iconSize))
                    .foregroundStyle(Color.happsGreenText)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                Text(item.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(item.message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(item.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.happsGreenText)
                                .accessibilityHidden(true)
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

    /// Custom dots instead of the built in indicator (hidden with indexDisplayMode .never) so they can be made accessible and adjustable.
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.happsGreenText : Color.secondary)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(pages.count)")
        .accessibilityHint("Swipe up or down to change page.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if page < pages.count - 1 { page += 1 }
            case .decrement: if page > 0 { page -= 1 }
            // Required for future cases of the direction enum.
            @unknown default: break
            }
        }
    }
}

/// Shows the tour once per account, the first time that account reaches the main app.
/// Decides whether to show the tour for the current user. @State holds whether the cover is showing.
private struct OnboardingGate: ViewModifier {
    let userID: String?
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            // Full screen cover so the tour sits above the whole app.
            .fullScreenCover(isPresented: $isShowing) {
                OnboardingView {
                    if let userID { OnboardingStore.markSeen(userID) }
                    isShowing = false
                }
                // Stops swipe-down dismissal, so the tour only ends through Skip or Get started and the seen flag is set.
                .interactiveDismissDisabled()
            }
            // initial: true also runs on first appearance, not only when the ID later changes (for example sign in as another user).
            .onChange(of: userID, initial: true) { _, newID in
                if let newID, !OnboardingStore.hasSeen(newID) {
                    isShowing = true
                }
            }
    }
}

/// Adds .onboarding(for: userID) to attach the tour to a view.
extension View {
    func onboarding(for userID: String?) -> some View {
        modifier(OnboardingGate(userID: userID))
    }
}

