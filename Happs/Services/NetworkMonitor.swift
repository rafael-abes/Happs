//
//  NetworkMonitor.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
import Foundation
import Network
import Combine
 
/// Watches connectivity with NWPathMonitor. `showOffline` only turns on after the
/// connection has been gone for 1.5 s, so a brief wobble (Wi-Fi to cellular) does not
/// flash the offline page.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected = true
    @Published private(set) var showOffline = false
    @Published private(set) var isChecking = false
 
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "happs.network.monitor")
    private var pendingOffline: Task<Void, Never>?
 
    init() {
        // The path handler runs on `queue`, so it is created in a nonisolated helper
        // and hops to the main actor with a plain Bool.
        Self.start(monitor, queue: queue) { [weak self] connected in
            Task { @MainActor in self?.update(connected: connected) }
        }
    }
 
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
