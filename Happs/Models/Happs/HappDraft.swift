//
//  HappDraft.swift
//  Happs
//
//  Created by Rafa Abes on 10/17/26.
//


import Foundation
import CoreLocation

/// The fields of the Happ form, so an external event can pre-fill it.
struct HappDraft {
    var title: String
    var details: String
    var location: String
    var coordinate: CLLocationCoordinate2D?
    var isOffCampus: Bool
    var category: HappCategory
    var startTime: Date
    var endTime: Date?
    
    init(
        title: String = "",
        details: String = "",
        location: String = "",
        coordinate: CLLocationCoordinate2D? = nil,
        isOffCampus: Bool = false,
        category: HappCategory = .happs,
        startTime: Date = Date(),
        endTime: Date? = nil
    ) {
        self.title = title
        self.details = details
        self.location = location
        self.coordinate = coordinate
        self.isOffCampus = isOffCampus
        self.category = category
        self.startTime = startTime
        self.endTime = endTime
    }
    
    static var blank: HappDraft {
        HappDraft(endTime: Date().addingTimeInterval(60 * 60))
    }
}

extension HappDraft {
    init(happ: Happ) {
        self.init(
            title: happ.title,
            details: happ.details,
            location: happ.location,
            coordinate: happ.coordinate,
            isOffCampus: happ.isOffCampus ?? false,
            category: happ.category,
            startTime: happ.startTime,
            endTime: happ.endTime
        )
    }
}