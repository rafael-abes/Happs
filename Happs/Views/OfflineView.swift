//
//  OfflineView.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//

import SwiftUI
 
/// Full-screen page shown while the device has no internet connection.
struct OfflineView: View {
    @ObservedObject var monitor: NetworkMonitor
 
    @ScaledMetric private var iconSize = 72.0
 
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: iconSize))
                .foregroundStyle(Color.happsGreen)
                .accessibilityHidden(true)
 
            Text("You're offline")
                .font(.title.bold())
 
            Text("Happs needs the internet to show live friends and Happs. Check your Wi-Fi or mobile data and we'll reconnect automatically.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
 
            Button {
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
                .background(Color.happsGreen, in: Capsule())
                .foregroundStyle(.white)
            }
            .disabled(monitor.isChecking)
            .padding(.horizontal, 40)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
    }
}
 
private struct OfflineOverlay: ViewModifier {
    @ObservedObject var monitor: NetworkMonitor
 
    func body(content: Content) -> some View {
        ZStack {
            content
            if monitor.showOffline {
                OfflineView(monitor: monitor)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: monitor.showOffline)
    }
}
 
extension View {
    /// Covers the whole screen with OfflineView while there is no connection.
    func offlineOverlay(_ monitor: NetworkMonitor) -> some View {
        modifier(OfflineOverlay(monitor: monitor))
    }
}
