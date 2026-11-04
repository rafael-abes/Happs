//
//  HappDraft.swift
//  Happs
//
//  Created by Rafa Abes on 10/17/26.
//


//  CODE OVERVIEW
//  -------------
//  A plain editable value used to pre-fill the create/edit Happ form. It is not stored in Firestore.
//  Several sources can produce one: a blank form, an existing Happ being edited, an external event
//  (such as Ticketmaster) or an AI-parsed sentence. Using a struct of simple fields means the form
//  can bind to a copy and only write back to the real model when the user saves.
//
import Foundation
import CoreLocation

/// The fields of the Happ form, so an external event can pre-fill it.
struct HappDraft {
    var title: String
    var details: String
    var location: String
    /// Map pin. CLLocationCoordinate2D is used here (UI side) while Happ stores plain latitude/longitude doubles.
    var coordinate: CLLocationCoordinate2D?
    var isOffCampus: Bool
    var category: HappCategory
    var startTime: Date
    var endTime: Date?
    
    /// Every parameter has a default so callers only pass what they know.
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
    
    /// An empty draft for "new Happ", ending one hour after now by default.
    /// A computed property so each access gets a fresh current time.
    static var blank: HappDraft {
        HappDraft(endTime: Date().addingTimeInterval(60 * 60))
    }
}

/// Conversion from a saved Happ. In an extension so the memberwise-style initialiser above is kept.
extension HappDraft {
    /// Copies a Happ's fields into a draft for editing. A nil isOffCampus becomes false.
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
