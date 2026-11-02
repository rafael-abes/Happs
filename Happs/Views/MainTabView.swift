//
//  MainTabView.swift
//  Happs
//
//  Created by Rafa Abes on 10/1/26.
//
import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var notificationStore: NotificationStore
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 30

    private enum Tab {
        case friends, happs, me
    }

    @State private var selectedTab: Tab = .happs

    var body: some View {
        VStack(spacing: 0) {

            // Main page
            Group {
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
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// What VoiceOver says for a tab. The Me tab includes the unread count from the badge.
    private func spokenName(for tab: Tab, label: String) -> String {
        guard tab == .me, notificationStore.unreadCount > 0 else { return label }
        let count = notificationStore.unreadCount
        return "\(label), \(count) unread \(count == 1 ? "notification" : "notifications")"
    }

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
