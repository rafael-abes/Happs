//
//  HappCategory+Filter.swift
//  Happs
//
//  Created by Rafa Abes on 10/3/26.
//

import MapKit

extension HappCategory {
    var pointOfInterestFilter: MKPointOfInterestFilter? {
        switch self {
        case .food: MKPointOfInterestFilter(including: [.cafe, .restaurant, .bakery, .foodMarket])
        case .sport: MKPointOfInterestFilter(including: [.fitnessCenter, .stadium, .park])
        case .study: MKPointOfInterestFilter(including: [.library, .university])
        case .happs: nil
        }
    }
}
