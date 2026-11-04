//
//  OfflineView.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//

// CODE OVERVIEW
// Full-screen "no internet" page. It is driven by NetworkMonitor (an ObservableObject passed in as
// @ObservedObject, because the monitor is owned elsewhere, not by this view). The view only shows state
// (isChecking, showOffline) and calls monitor.retry(). The offlineOverlay modifier at the bottom lets the
// app root cover any content with this page using a ZStack, instead of navigating to it, so the user
// returns to exactly where they were once the connection is back.
import SwiftUI

/// Full-screen page shown while the device has no internet connection.
struct OfflineView: View {
    // @ObservedObject: observes an object owned by someone else. @StateObject would be for the owner.
    @ObservedObject var monitor: NetworkMonitor

    // Icon size scales with the user's Dynamic Type setting.
    @ScaledMetric private var iconSize = 72.0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: iconSize))
                    .foregroundStyle(Color.happsGreenText)
                    .padding(.top, 60)
                    .accessibilityHidden(true)

                Text("You're offline")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("Happs needs the internet to show live friends and Happs. Check your Wi-Fi or mobile data and we'll reconnect automatically.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)

                Button {
                    // Button actions are synchronous, so a Task wraps the async retry call.
                    Task { await monitor.retry() }
                } label: {
                    HStack(spacing: 8) {
                        if monitor.isChecking {
                            ProgressView().tint(.white)
                        }
                        Text(monitor.isChecking ? "Checking..." : "Try again")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.happsGreenFill, in: Capsule())
                    .foregroundStyle(.white)
                }
                .disabled(monitor.isChecking)
                .padding(.horizontal, 40)
                .padding(.top, 8)
                .accessibilityLabel("Try again")
                .accessibilityValue(monitor.isChecking ? "Checking" : "")
                .accessibilityHint("Checks your connection again.")
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
    }
}

/// ViewModifier that layers OfflineView over any content while monitor.showOffline is true. Private, used through the offlineOverlay extension.
private struct OfflineOverlay: ViewModifier {
    @ObservedObject var monitor: NetworkMonitor
    // Reads the Reduce Motion setting so animation can be skipped.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Content stays in the hierarchy underneath, so its state is kept while the overlay is up.
        ZStack {
            content
            if monitor.showOffline {
                OfflineView(monitor: monitor)
                    .transition(reduceMotion ? .identity : .opacity)
                    // Keeps the overlay above content so the transition animates correctly when it is inserted or removed.
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: monitor.showOffline)
        .onChange(of: monitor.showOffline) { _, isShowing in
            AccessibilityNotification.Announcement(isShowing ? "You're offline." : "Back online.").post()
        }
    }
}

/// Adds the .offlineOverlay(monitor) call syntax.
extension View {
    /// Covers the whole screen with OfflineView while there is no connection.
    func offlineOverlay(_ monitor: NetworkMonitor) -> some View {
        modifier(OfflineOverlay(monitor: monitor))
    }
}

