//
//  Happ+map.swift
//  Happs
//
//  Created by Rafa Abes on 10/9/26.
//
// CODE OVERVIEW
// Map-related presentation helpers for the Happ model, written as extensions so the model does
// not need to import MapKit or SwiftUI styling itself. `coordinate` converts the stored optional
// latitude and longitude to a CoreLocation value, and HappCategory gets its icon and colour
// (used by HappPin and HappCard). Category is shown by shape (icon) as well as colour.
import SwiftUI
import CoreLocation

/// Adds a map coordinate to a Happ.
extension Happ {
    /// The Happ's location as a CLLocationCoordinate2D, or nil if it has no latitude and longitude (the fields are optional).
    var coordinate: CLLocationCoordinate2D? {
        // Both must exist; either one missing means no pin can be placed.
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Visual identity of each category.
extension HappCategory {
    /// SF Symbol drawn on pins and cards for this category.
    var symbolName: String {
        switch self {
        case .food: "fork.knife"
        case .sport: "figure.run"
        case .study: "book.fill"
        case .happs: "person.3.fill"
        }
    }
    
    /// Tint colour for this category's pins, badges and outlines.
    var tint: Color {
        switch self {
        case .food: .orange
        case .sport: .blue
        case .study: .purple
        case .happs: .green
        }
    }
}
