//
//  ClockTicker.swift
//  Happs
//
//  Created by Rafa Abes on 10/12/26.
//

import SwiftUI

private struct ExpiryClock: ViewModifier {
    @Binding var now: Date
    let boundaries: [Date]
    @Environment(\.scenePhase) private var scenePhase
    
    private var nextBoundary: Date? {
        boundaries.filter { $0 > now }.min()
    }
    
    func body(content: Content) -> some View {
        content
            .task(id: nextBoundary) {
                now = Date()
                guard let target = boundaries.filter({ $0 > Date() }).min() else { return }
                let delay = max(target.timeIntervalSinceNow, 0) + 0.25
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                now = Date()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = Date() }
            }
    }
}

extension View {
    /// Keeps `now` current at the moments a Happ goes live or ends.
    func expiryClock(_ now: Binding<Date>, boundaries: [Date]) -> some View {
        modifier(ExpiryClock(now: now, boundaries: boundaries))
    }
}
