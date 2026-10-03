//
//  MainTabView.swift
//  Happs
//
//  Created by Rafa Abes on 10/1/26.
//
import SwiftUI

struct MainTabView: View {

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
                imageName: "friendsLogo",
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
                imageName: "meLogo",
                label: "Me"
            )
        }
        .padding(.horizontal, 40)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
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
                    .frame(width: 30, height: 30)

                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(
                selectedTab == tab
                ? .green
                : .secondary
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background {
                if selectedTab == tab {
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
