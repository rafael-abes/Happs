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
    @StateObject private var authService = AuthService()
    @StateObject private var happStore = HappStore()
    @StateObject private var friendStore = FriendStore()
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var locationService = LocationService()
    
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
        .environmentObject(authService)
        .environmentObject(happStore)
        .environmentObject(friendStore)
        .environmentObject(profileStore)
        .environmentObject(locationService)
        .onChange(of: authService.user?.uid, initial: true) { _, userID in
            if let userID {
                happStore.startListening()
                friendStore.startListening(for: userID)
                profileStore.startListening(userID: userID)
//                locationService.requestPermission()
//                locationService.startSharing(userID: userID)
            } else {
                happStore.stopListening()
                friendStore.stopListening()
                profileStore.stopListening()
                locationService.stopSharing()
            }
        }
        .onChange(of: profileStore.profile?.isVisible) { _, isVisible in
            locationService.isInvisible = (isVisible == false)
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
