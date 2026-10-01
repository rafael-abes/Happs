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
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .friends: FriendsPlaceholderView()
                case .happs: HappsListView()
                case .me: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            tabBar
        }
    }
    
    private var tabBar: some View {
        HStack {
            tabButton(.friends, systemImage: "person.2.fill", label: "Friends")
            
            Spacer()
            
            Button { selectedTab = .happs } label: {
                VStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 28, height: 28)
                    Text("Happs")
                        .font(.caption2)
                        .foregroundStyle(selectedTab == .happs ? .green : .secondary)
                }
            }
            
            Spacer()
            
            tabButton(.me, systemImage: "person.fill", label: "Me")
        }
        .padding(.horizontal, 40)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .background(.bar)
    }
    
    private func tabButton(_ tab: Tab, systemImage: String, label: String) -> some View {
        Button { selectedTab = tab } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(selectedTab == tab ? .green : .secondary)
        }
    }
}

private struct FriendsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Friends Coming Soon",
                systemImage: "person.2",
                description: Text("Friend requests and your friends list will live here.")
            )
            .navigationTitle("Friends")
        }
    }
}
