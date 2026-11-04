//
//  MainTabView.swift
//  Happs
//
//  Created by Rafa Abes on 10/1/26.
//
// CODE OVERVIEW
// The root screen once the user is signed in (ContentView shows it). It is a custom tab bar
// switching between Friends, Happs and Me, rather than SwiftUI's TabView.
// A hand built bar gives full control over the icons (custom light and dark assets), the green
// selected capsule and the unread badge (assumed reason for not using TabView). The cost is that
// accessibility traits and sizing have to be added by hand, which this file does.
// Only the selected tab's view is created at a time (a switch), so a tab's @State resets when
// you leave it. The badge count comes from NotificationStore.unreadCount.
import SwiftUI

/// Signed in shell: the current tab's screen above a custom bottom tab bar.
struct MainTabView: View {
    // Source of the unread count shown as a badge on the Me tab.
    @EnvironmentObject private var notificationStore: NotificationStore
    // Same key the app uses for the dark mode setting; here it only picks the light or dark icon variant.
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    // Icon size scales with Dynamic Type instead of staying fixed.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 30

    /// The three tabs.
    private enum Tab {
        case friends, happs, me
    }

    // Starts on the Happs tab.
    @State private var selectedTab: Tab = .happs

    var body: some View {
        VStack(spacing: 0) {

            // Main page
            Group {
                // Only the active tab is built.
                switch selectedTab {
                case .friends:
                    FriendsListView()

                case .happs:
                    HappsListView()

                case .me:
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            tabBar
        }
    }

    /// The bottom bar, built from three tabButton calls separated by spacers.
    private var tabBar: some View {
        HStack {

            // MARK: Friends
            tabButton(
                .friends,
                imageName: prefersDarkMode ? "friendsLogoLight" : "friendsLogo",
                label: "Friends"
            )

            Spacer()

            // MARK: Happs
            tabButton(
                .happs,
                imageName: "happsLogo",
                label: "Happs"
            )

            Spacer()

            // MARK: Me
            tabButton(
                .me,
                imageName: prefersDarkMode ? "meLogoLight" : "meLogo",
                label: "Me"
            )
        }
        .padding(.horizontal, 40)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
        // Caps the bar's text growth (see the accessibility notes above); screen content is not capped.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// What VoiceOver says for a tab. The Me tab includes the unread count from the badge.
    private func spokenName(for tab: Tab, label: String) -> String {
        guard tab == .me, notificationStore.unreadCount > 0 else { return label }
        let count = notificationStore.unreadCount
        return "\(label), \(count) unread \(count == 1 ? "notification" : "notifications")"
    }

    /// One tab button: icon (with badge on Me), label, selected styling and accessibility traits.
    private func tabButton(
        _ tab: Tab,
        imageName: String,
        label: String
    ) -> some View {

        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
                    .overlay(alignment: .topTrailing) {
                        if tab == .me && notificationStore.unreadCount > 0 {
                            Text(
                                notificationStore.unreadCount > 99
                                    ? "99+"
                                    : "\(notificationStore.unreadCount)"
                            )
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.happsRedFill, in: Capsule())
                            .offset(x: 8, y: -5)
                            .fixedSize()
                        }
                    }

                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(
                selectedTab == tab
                    ? Color.happsGreenText
                    : Color.secondary
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background {
                if selectedTab == tab {
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenName(for: tab, label: label))
        .accessibilityHint("Opens the \(label) tab.")
        .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)
    }

}

