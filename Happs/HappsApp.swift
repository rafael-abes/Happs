//
//  HappsApp.swift
//  Happs
//
//  Created by Rafa Abes on 9/10/26.
//
//  CODE OVERVIEW
//  -------------
//  App entry point (@main). SwiftUI has no AppDelegate by default, so AppDelegate is attached with
//  @UIApplicationDelegateAdaptor to get the UIKit lifecycle hooks Firebase and Google Sign-In need:
//  configuring Firebase at launch, receiving the Google Sign-In redirect URL, and showing
//  notifications while the app is open. App Check is configured here too, before Firebase starts,
//  so that Firestore and AI calls carry an App Check token. HappsApp itself only hosts ContentView
//  and the global offline banner.
//
import SwiftUI
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import UserNotifications
import FirebaseAppCheck

/// Release builds use App Attest. It needs a paid Apple Developer account,
/// so on a free Personal Team only Debug builds can pass App Check.
/// Tells App Check which provider to use for Release builds. App Check proves requests come from the
/// genuine app, so the backend can reject scripted or copied clients.
final class HappsAppCheckFactory: NSObject, AppCheckProviderFactory {
    /// Called by Firebase when it needs a provider for the given app instance.
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}

/// UIKit-style app delegate bridged into SwiftUI. Also the notification centre delegate so it can
/// control how notifications are shown in the foreground.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Runs once at launch. Configures App Check and Firebase, then registers for notification callbacks.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Skip configuration when the plist is absent; ContentView then shows FirebaseSetupView
        // instead of crashing inside FirebaseApp.configure().
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            // The provider factory must be set BEFORE FirebaseApp.configure().
            // Debug builds use the debug provider (works in the simulator and on free accounts).
            #if DEBUG
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
            #else
            AppCheck.setAppCheckProviderFactory(HappsAppCheckFactory())
            #endif
            FirebaseApp.configure()
        }
        // Setting the delegate is what makes willPresent below get called.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Receives the redirect URL after the Google Sign-In web flow and hands it to the SDK,
    /// which completes the sign-in. Returns whether the SDK recognised the URL.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// Without this, iOS silently swallows notifications while the app is on screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

/// The app's entry point. Owns the NetworkMonitor so connectivity is tracked for the whole session.
@main
struct HappsApp: App {
    /// Connects the UIKit AppDelegate above to this SwiftUI app.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// @StateObject so one monitor lives as long as the app, not recreated on each body refresh.
    @StateObject private var networkMonitor = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Overlay at the root so the offline banner appears over every screen.
                .offlineOverlay(networkMonitor)
        }
    }
}
