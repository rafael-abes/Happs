//
//  Campus+Region.swift
//  Happs
//
//  Created by Rafa Abes on 10/9/26.
//

import MapKit

extension LocationService {
    static var campusRegion: MKCoordinateRegion {
        let lats = campusBoundary.map(\.latitude)
        let lons = campusBoundary.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion()
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.6, longitudeDelta: (maxLon - minLon) * 1.6)
        )
    }
}
