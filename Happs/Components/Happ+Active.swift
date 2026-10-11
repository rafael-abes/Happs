//
//  Happ+Active.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//
import Foundation

extension Happ {
    /// Active from one hour before the start time until three hours after it.
    var isActiveNow: Bool {
        let now = Date()
        return startTime <= now.addingTimeInterval(60 * 60)
            && startTime >= now.addingTimeInterval(-3 * 60 * 60)
    }
}
