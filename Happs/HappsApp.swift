//
//  HappsApp.swift
//  Happs
//
//  Created by Rafa Abes on 9/10/26.
//
import SwiftUI
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
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

@main
struct HappsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
