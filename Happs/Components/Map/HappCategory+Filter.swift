//
//  HappCategory+Filter.swift
//  Happs
//
//  Created by Rafa Abes on 10/3/26.
//

// CODE OVERVIEW
// Maps each HappCategory to an MKPointOfInterestFilter so a map can highlight only the kinds of
// places that fit the category (for example cafes for food). It is an extension to keep MapKit
// out of the model. A nil filter means "no restriction".
import MapKit

/// MapKit integration for categories.
extension HappCategory {
    /// Which MapKit points of interest to include for this category, or nil for no filtering (the generic `.happs` category).
    var pointOfInterestFilter: MKPointOfInterestFilter? {
        switch self {
        case .food: MKPointOfInterestFilter(including: [.cafe, .restaurant, .bakery, .foodMarket])
        case .sport: MKPointOfInterestFilter(including: [.fitnessCenter, .stadium, .park])
        case .study: MKPointOfInterestFilter(including: [.library, .university])
        case .happs: nil
        }
    }
}
