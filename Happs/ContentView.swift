//
//  ContentView.swift
//  Happs
//
//  Created by Rafa Abes on 9/10/26.
//
//  CODE OVERVIEW
//  -------------
//  ContentView is the root view of the app (HappsApp shows it in the WindowGroup). It decides between
//  three screens: a setup message if Firebase is not configured, the login screen if nobody is signed
//  in, or the main tab UI. AuthenticatedRootView owns every store and service as a @StateObject
//  (created once, kept alive for the whole session) and injects them with .environmentObject so any
//  child view can read them. It also starts and stops the Firestore snapshot listeners whenever the
//  signed-in user changes, so no data is read while signed out.
//
import SwiftUI
import FirebaseCore
import FirebaseAuth

/// Top-level view: picks the setup screen or the real app, and applies the saved light/dark preference.
struct ContentView: View {
    /// Persisted in UserDefaults by @AppStorage, so the theme choice survives relaunches.
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

/// Owns all shared stores and wires them to the signed-in user. Kept separate from ContentView so the
/// stores are only created once Firebase is known to be configured (assumed reason: the stores use Firebase).
private struct AuthenticatedRootView: View {
    /// Used to refresh location and the friend clock when the app returns to the foreground.
    @Environment(\.scenePhase) private var scenePhase

    // @StateObject (not @ObservedObject) so each store is created once and survives view re-renders.
    // Children receive them via .environmentObject below instead of being passed through initialisers.

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
        // Three-way switch driven by AuthService: still checking, signed out, or signed in.
        Group {
            if authService.isCheckingAuthentication {
                ProgressView("Checking your account…")
            } else if authService.user == nil {
                AuthenticationView()
            } else {
                MainTabView()
            }

        }
        // Show first-run onboarding keyed to the user id, so each account sees it once.
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
        // Fetch the AI configuration once when the view appears (.task is cancelled if it disappears).
        .task { await aiService.refreshConfig() }
        // initial: true also runs this on first appearance, covering an already-restored session.
        // A non-nil uid means signed in: start every listener. nil means signed out: stop them all.
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
                // Remove scheduled local reminders so a signed-out device stops notifying.
                Task { await RecapReminders.removeAll() }
            }
        }
        // Safety sets are pushed into the stores on every change; the stores do the actual filtering.
        // The blocked list is mapped to ids so the observer fires only when who is blocked changes.
        .onChange(of: safetyStore.blocked.map(\.id), initial: true) { _, _ in pushSafetyState() }
        .onChange(of: safetyStore.hiddenContentIDs, initial: true) { _, _ in pushSafetyState() }
        .onChange(of: happStore.allHapps.map(\.id), initial: true) { _, _ in syncReminders() }
        .onChange(of: authService.user?.uid) { _, _ in syncReminders() }
        // Friend locations are only shown while this user is allowed to publish their own (on campus).
        .onChange(of: locationService.isPublishedOnCampus) { _, allowed in
            friendStore.setLocationAccess(allowed)
        }
        .onChange(of: scenePhase) { _, phase in
            // Only act on returning to the foreground; ignore .inactive and .background.
            guard phase == .active else { return }
            locationService.refreshNow()
            friendStore.refreshClock()
        }
        // Recap listeners are per-user, so drop them whenever the account changes.
        .onChange(of: authService.user?.uid) { _, _ in recapStore.stopAll() }
    }
}

/// Helper methods split out of the main struct to keep the view body readable. fileprivate because
/// only this file needs them.
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

    /// Reschedules the local "share your photos" reminders for the current user's Happs.
    /// Does nothing when signed out. Runs async work in a Task because the body callbacks are synchronous.
    fileprivate func syncReminders() {
        guard let userID = authService.user?.uid else { return }
        Task { await RecapReminders.sync(happs: happStore.allHapps, userID: userID) }
    }
}

/// Shown instead of the app when GoogleService-Info.plist is missing (see AppDelegate, which only
/// configures Firebase if that file exists). Avoids crashing stores that need Firebase.
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
