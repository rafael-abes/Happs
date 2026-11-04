//
//  Happ+Active.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
// CODE OVERVIEW
// Time rules for a Happ, added as extensions so the Happ model stays a plain data type. All the
// "is it live" logic is here in one place: a Happ with no end time lasts 3 hours, and it counts
// as active from one hour before it starts until it ends. The `date` parameters default to now
// but can be passed in, which makes the rules easy to test and lets views supply their own `now`
// (see ClockTicker.swift). clockBoundaries lists the instants at which those answers change.
import Foundation

extension Happ {
    /// A Happ with no end time stays up this long after it starts.
    static let defaultDuration: TimeInterval = 3 * 60 * 60
    
    /// True when the host chose an end time.
    var hasEndTime: Bool { endTime != nil }
    
    /// The real end: the chosen end time, or start plus the default duration when none was set.
    var effectiveEndTime: Date {
        endTime ?? startTime.addingTimeInterval(Self.defaultDuration)
    }
    
    /// True once `date` is at or after the effective end.
    func hasEnded(at date: Date = Date()) -> Bool {
        date >= effectiveEndTime
    }
    
    /// Active from one hour before the start until the end.
    func isActive(at date: Date = Date()) -> Bool {
        date >= startTime.addingTimeInterval(-60 * 60) && date < effectiveEndTime
    }
    
    /// Human-readable time range for lists and details, for example "Nov 2, 5:00 PM to 7:00 PM".
    /// Shows the date only once when start and end fall on the same day, and says "open-ended" when there is no end time.
    var timeRangeText: String {
        let start = startTime.formatted(date: .abbreviated, time: .shortened)
        guard let endTime else { return "\(start) · open-ended" }
        if Calendar.current.isDate(startTime, inSameDayAs: endTime) {
            return "\(start) to \(endTime.formatted(date: .omitted, time: .shortened))"
        }
        return "\(start) to \(endTime.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// Lets any collection of Happs report all its start and end boundaries, to be given to `expiryClock`.
extension Sequence where Element == Happ {
    /// Every moment a Happ starts counting as active or stops being live.
    var clockBoundaries: [Date] {
        // flatMap flattens the two dates per Happ into one array. -60 * 60 is the one-hour early-activation window used in isActive.
        flatMap { [$0.startTime.addingTimeInterval(-60 * 60), $0.effectiveEndTime] }
    }
}
