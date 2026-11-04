//
//  UserStatus+Style.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

// CODE OVERVIEW
// Presentation-only extension on the UserStatus enum (the model type lives elsewhere). It keeps
// colours and SF Symbol names out of the model so the data layer does not depend on SwiftUI
// styling, while every view that shows a status (avatars, map pins, lists) reads the same values.
// Switches are exhaustive with no default, so adding a new status forces a compile error here
// until its colour and symbol are chosen.
import SwiftUI

/// Visual styling for each availability status.
extension UserStatus {
    /// Dot, ring or border colour for this status. Not for text (see the contrast note above).
    var color: Color {
        switch self {
        case .available: .green
        case .inClass: .orange
        case .busy: .red
        case .doNotDisturb: .gray
        }
    }

    /// Shape cue so status is never conveyed by colour alone.
    var symbolName: String {
        switch self {
        case .available: "checkmark"
        case .inClass: "book.fill"
        case .busy: "clock.fill"
        case .doNotDisturb: "moon.fill"
        }
    }
}

