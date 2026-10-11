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
    
    @EnvironmentObject private var notificationStore: NotificationStore
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @State private var selectedTab: Tab = .happs
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FriendsListView()
                .tabItem { tabLabel("Friends", imageName: prefersDarkMode ? "friendsLogoLight" : "friendsLogo") }
                .tag(Tab.friends)
            
            HappsListView()
                .tabItem { tabLabel("Happs", imageName: "happsLogo") }
                .tag(Tab.happs)
            
            ProfileView()
                .tabItem { tabLabel("Me", imageName: prefersDarkMode ? "meLogoLight" : "meLogo") }
                .tag(Tab.me)
                .badge(notificationStore.unreadCount)
        }
        .tint(.green)
    }
    
    private func tabLabel(_ title: String, imageName: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(imageName).renderingMode(.original)
        }
    }
}
