//
//  Happ+Active.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//
import Foundation

extension Happ {
    /// A Happ with no end time stays up this long after it starts.
    static let defaultDuration: TimeInterval = 3 * 60 * 60
    
    var hasEndTime: Bool { endTime != nil }
    
    var effectiveEndTime: Date {
        endTime ?? startTime.addingTimeInterval(Self.defaultDuration)
    }
    
    func hasEnded(at date: Date = Date()) -> Bool {
        date >= effectiveEndTime
    }
    
    /// Active from one hour before the start until the end.
    func isActive(at date: Date = Date()) -> Bool {
        date >= startTime.addingTimeInterval(-60 * 60) && date < effectiveEndTime
    }
    
    var timeRangeText: String {
        let start = startTime.formatted(date: .abbreviated, time: .shortened)
        guard let endTime else { return "\(start) · open-ended" }
        if Calendar.current.isDate(startTime, inSameDayAs: endTime) {
            return "\(start) to \(endTime.formatted(date: .omitted, time: .shortened))"
        }
        return "\(start) to \(endTime.formatted(date: .abbreviated, time: .shortened))"
    }
}

extension Sequence where Element == Happ {
    /// Every moment a Happ starts counting as active or stops being live.
    var clockBoundaries: [Date] {
        flatMap { [$0.startTime.addingTimeInterval(-60 * 60), $0.effectiveEndTime] }
    }
}
