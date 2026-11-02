//
//  ContentView.swift
//  Happs
//
//  Created by Rafa Abes on 9/10/26.
//

//
//  SAFETY, FOMO AND ACCOUNT DELETION WIRING
//  ----------------------------------------
//  - SafetyStore is created once and shared. It listens while signed in (blocked people and hidden
//    content) and its sets are pushed into the Happ, friend, group, notification and recap stores,
//    which do the actual hiding.
//  - RecapReminders.sync reschedules the "share your photos" reminders whenever the Happ list or
//    user changes. Sign-out clears them.
//  - On sign-out or account deletion every listener stops, which also removes the user's data from
//    memory.
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
    @StateObject private var recapStore = RecapStore()
    @StateObject private var safetyStore = SafetyStore()

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
        .environmentObject(recapStore)
        .environmentObject(safetyStore)
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
                safetyStore.startListening(userID: userID)
            } else {
                happStore.stopListening()
                friendStore.stopListening()
                profileStore.stopListening()
                groupStore.stopListening()
                notificationStore.stopListening()
                locationService.stopSharing()
                safetyStore.stopListening()
                Task { await RecapReminders.removeAll() }
            }
        }
        .onChange(of: safetyStore.blocked.map(\.id), initial: true) { _, _ in pushSafetyState() }
        .onChange(of: safetyStore.hiddenContentIDs, initial: true) { _, _ in pushSafetyState() }
        .onChange(of: happStore.allHapps.map(\.id), initial: true) { _, _ in syncReminders() }
        .onChange(of: authService.user?.uid) { _, _ in syncReminders() }
        .onChange(of: locationService.isPublishedOnCampus) { _, allowed in
            friendStore.setLocationAccess(allowed)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            locationService.refreshNow()
            friendStore.refreshClock()
        }
        .onChange(of: authService.user?.uid) { _, _ in recapStore.stopAll() }
    }
}

extension AuthenticatedRootView {
    /// Hands the blocked and hidden sets to the stores that hide content.
    fileprivate func pushSafetyState() {
        let blocked = safetyStore.blockedIDs
        let hidden = safetyStore.hiddenContentIDs
        happStore.blockedIDs = blocked
        happStore.hiddenIDs = hidden
        friendStore.blockedIDs = blocked
        groupStore.blockedIDs = blocked
        notificationStore.blockedIDs = blocked
        recapStore.blockedIDs = blocked
        recapStore.hiddenIDs = hidden
    }

    fileprivate func syncReminders() {
        guard let userID = authService.user?.uid else { return }
        Task { await RecapReminders.sync(happs: happStore.allHapps, userID: userID) }
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
