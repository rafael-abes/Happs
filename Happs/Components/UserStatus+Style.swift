//
//  UserStatus+Style.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

import SwiftUI

extension UserStatus {
    var color: Color {
        switch self {
        case .available: .green
        case .inClass: .orange
        case .busy: .red
        case .doNotDisturb: .gray
        }
    }
}
