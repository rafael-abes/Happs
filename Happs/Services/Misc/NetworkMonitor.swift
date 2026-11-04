//
//  NetworkMonitor.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
//  CODE OVERVIEW
//  -------------
//  Tracks whether the device is online using Apple's Network framework (NWPathMonitor). HappsApp owns
//  one instance and passes it to the offlineOverlay modifier, which shows an offline page. It is an
//  ObservableObject with @Published values so SwiftUI updates automatically, and @MainActor so those
//  values are only changed on the main thread. A short delay before showing "offline" avoids flicker.
//
import Foundation
import Network
import Combine
 
/// Watches connectivity with NWPathMonitor. `showOffline` only turns on after the
/// connection has been gone for 1.5 s, so a brief wobble (Wi-Fi to cellular) does not
/// flash the offline page.
@MainActor
final class NetworkMonitor: ObservableObject {
    /// Raw connection state (starts true so the UI does not flash offline at launch).
    @Published private(set) var isConnected = true
    /// What the overlay actually observes: true only after the delay described above.
    @Published private(set) var showOffline = false
    /// True while the retry button is waiting, so the UI can show progress.
    @Published private(set) var isChecking = false
 
    /// Apple's connectivity watcher; it reports on a background queue.
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "happs.network.monitor")
    /// The delayed task that will flip showOffline; cancelled if the connection returns first.
    private var pendingOffline: Task<Void, Never>?
 
    init() {
        // The path handler runs on `queue`, so it is created in a nonisolated helper
        // and hops to the main actor with a plain Bool.
        Self.start(monitor, queue: queue) { [weak self] connected in
            // [weak self] avoids a retain cycle, and Task { @MainActor } hops back to the main thread.
            Task { @MainActor in self?.update(connected: connected) }
        }
    }
 
    /// Stops the monitor when the object goes away.
    deinit {
        monitor.cancel()
    }
 
    /// "Try again" button: re-reads the current path after a short pause.
    func retry() async {
        isChecking = true
        try? await Task.sleep(for: .seconds(1))
        update(connected: monitor.currentPath.status == .satisfied)
        isChecking = false
    }
 
    /// Applies a new connection state. Going online hides the overlay immediately; going offline waits
    /// 1.5 s first, and any earlier pending wait is cancelled so waits never stack up.
    private func update(connected: Bool) {
        isConnected = connected
        pendingOffline?.cancel()
        if connected {
            showOffline = false
        } else if !showOffline {
            pendingOffline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.showOffline = true
            }
        }
    }
 
    /// Starts the monitor. nonisolated and static so the callback closure is not tied to the main actor
    /// (it runs on `queue`); @Sendable because it crosses threads.
    nonisolated private static func start(
        _ monitor: NWPathMonitor,
        queue: DispatchQueue,
        onChange: @escaping @Sendable (Bool) -> Void
    ) {
        monitor.pathUpdateHandler = { path in
            onChange(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }
}
