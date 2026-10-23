//
//  ContentView.swift
//  Happs
//
//  Created by Rafa Abes on 9/10/26.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

struct ContentView: View {
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    
    var body: some View {
        Group {
            if FirebaseApp.app() == nil {
                FirebaseSetupView()
            } else {
                AuthenticatedRootView()
            }
        }
        .preferredColorScheme(prefersDarkMode ? .dark : .light)
    }
}

private struct AuthenticatedRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var authService = AuthService()
    @StateObject private var happStore = HappStore()
    @StateObject private var friendStore = FriendStore()
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var locationService = LocationService()
    @StateObject private var groupStore = GroupStore()
    @StateObject private var notificationStore = NotificationStore()
    @StateObject private var aiService = AIService()
    
    var body: some View {
        Group {
            if authService.isCheckingAuthentication {
                ProgressView("Checking your account…")
            } else if authService.user == nil {
                AuthenticationView()
            } else {
                MainTabView()
            }
            
        }
        .onboarding(for: authService.user?.uid)
        .environmentObject(authService)
        .environmentObject(happStore)
        .environmentObject(friendStore)
        .environmentObject(profileStore)
        .environmentObject(locationService)
        .environmentObject(groupStore)
        .environmentObject(notificationStore)
        .environmentObject(aiService)
        .task { await aiService.refreshConfig() }
        .onChange(of: authService.user?.uid, initial: true) { _, userID in
            if let userID {
                happStore.startListening()
                friendStore.startListening(for: userID)
                profileStore.startListening(userID: userID)
                groupStore.startListening(for: userID)
                notificationStore.requestPermission()
                notificationStore.startListening(for: userID)
                locationService.requestPermission()
                locationService.startSharing(userID: userID)
            } else {
                happStore.stopListening()
                friendStore.stopListening()
                profileStore.stopListening()
                groupStore.stopListening()
                notificationStore.stopListening()
                locationService.stopSharing()
            }
        }
        .onChange(of: locationService.isPublishedOnCampus) { _, allowed in
            friendStore.setLocationAccess(allowed)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            locationService.refreshNow()
            friendStore.refreshClock()
        }
    }
}

private struct FirebaseSetupView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Firebase Setup Required", systemImage: "flame.fill")
        } description: {
            Text("Add GoogleService-Info.plist to the Happs target, then run the app again.")
        }
        .padding()
    }
}
