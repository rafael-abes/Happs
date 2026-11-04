//
//  ClockTicker.swift
//  Happs
//
//  Created by Rafa Abes on 10/12/26.
//

// CODE OVERVIEW
// A ViewModifier that keeps a `now` Date binding correct without a repeating timer. Instead of
// ticking every second, it sleeps until the next moment something changes (a Happ becoming
// active or ending, from Happ+Active.swift clockBoundaries) and then refreshes `now` once.
// This saves battery and work compared with a one second timer. Screens attach it through the
// View extension at the bottom: HappsListView, HappsMapView and CampusLockedView use it.
import SwiftUI

/// The modifier itself. It is private; other files use the `expiryClock` extension instead.
private struct ExpiryClock: ViewModifier {
    /// The parent's `now` value. A Binding so the modifier can write back to the parent's @State.
    @Binding var now: Date
    /// Times at which the UI may need to change, such as start minus one hour and end of each Happ.
    let boundaries: [Date]
    // Used to refresh `now` when the app returns to the foreground (assumed reason: the sleep may have run long while the app was in the background).
    @Environment(\.scenePhase) private var scenePhase
    
    /// The earliest boundary still in the future, or nil when there is nothing left to wait for.
    private var nextBoundary: Date? {
        boundaries.filter { $0 > now }.min()
    }
    
    func body(content: Content) -> some View {
        content
            // .task(id:) cancels and restarts this work whenever nextBoundary changes, so the sleep always targets the right time.
            .task(id: nextBoundary) {
                // Refresh straight away in case time has moved on since the view was built.
                now = Date()
                guard let target = boundaries.filter({ $0 > Date() }).min() else { return }
                // The extra 0.25 s makes sure we wake just after the boundary, so the comparison `date >= boundary` is true.
                let delay = max(target.timeIntervalSinceNow, 0) + 0.25
                try? await Task.sleep(for: .seconds(delay))
                // Task.sleep ends early (try? swallows the error) if the task was cancelled; do not write a stale value then.
                guard !Task.isCancelled else { return }
                now = Date()
            }
            // Two-parameter onChange (old, new) is the iOS 17 form.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = Date() }
            }
    }
}

extension View {
    /// Keeps `now` current at the moments a Happ goes live or ends.
    /// - Parameters:
    ///   - now: Binding to the date the view uses for "is it live yet" checks.
    ///   - boundaries: Dates at which `now` must be refreshed.
    func expiryClock(_ now: Binding<Date>, boundaries: [Date]) -> some View {
        modifier(ExpiryClock(now: now, boundaries: boundaries))
    }
}
