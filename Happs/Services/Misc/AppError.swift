//
//  AppError.swift
//  Happs
//
//  Created by Rafa Abes on 9/22/26.
//

//  CODE OVERVIEW
//  -------------
//  App-specific errors that the UI can show directly. Conforming to LocalizedError means an alert can
//  display errorDescription instead of a generic system message.
//
import Foundation

/// Errors thrown by the Happ stores and forms.
enum AppError: LocalizedError {
    /// Validation failure; the associated String is the message to show.
    case invalidForm(String)
    /// The Happ was deleted before the action finished.
    case happNotFound
    
    /// Text shown to the user.
    var errorDescription: String? {
        switch self {
        case .invalidForm(let message): message
        case .happNotFound: "This happ no longer exists."
        }
    }
}
