//
//  Happ+map.swift
//  Happs
//
//  Created by Rafa Abes on 10/9/26.
//
import SwiftUI
import CoreLocation

extension Happ {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension HappCategory {
    var symbolName: String {
        switch self {
        case .food: "fork.knife"
        case .sport: "figure.run"
        case .study: "book.fill"
        case .happs: "person.3.fill"
        }
    }
    
    var tint: Color {
        switch self {
        case .food: .orange
        case .sport: .blue
        case .study: .purple
        case .happs: .green
        }
    }
}
