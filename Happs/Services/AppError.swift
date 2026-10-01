//
//  AppError.swift
//  Happs
//
//  Created by Rafa Abes on 9/22/26.
//

import Foundation

enum AppError: LocalizedError {
    case invalidForm(String)
    case happNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidForm(let message): message
        case .happNotFound: "This happ no longer exists."
        }
    }
}
