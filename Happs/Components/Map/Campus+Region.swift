//
//  Campus+Region.swift
//  Happs
//
//  Created by Rafa Abes on 10/9/26.
//

// CODE OVERVIEW
// Two computed helpers added to LocationService (an extension, so the service file itself is
// not changed) that turn the campus boundary polygon into a centre point and a map region.
// The map screens use the region as the initial camera position, so the camera always frames
// the campus without hard-coding coordinates a second time.
import MapKit

extension LocationService {
    /// Centre of the campus, taken as the plain average of the boundary corners (a centroid of the
    /// vertices, not of the area; good enough for a roughly convex campus outline).
    static var campusCenter: CLLocationCoordinate2D {
        // `points.count` is converted to Double so the division below is floating point.
        let points = campusBoundary
        let count = Double(points.count)
        return CLLocationCoordinate2D(
            latitude: points.map(\.latitude).reduce(0, +) / count,
            longitude: points.map(\.longitude).reduce(0, +) / count
        )
    }
    
    /// Map region that frames the whole campus: the bounding box of the boundary, centred, with
    /// the span multiplied by 1.6 so there is a margin around the edges.
    static var campusRegion: MKCoordinateRegion {
        let lats = campusBoundary.map(\.latitude)
        let lons = campusBoundary.map(\.longitude)
        // min()/max() return optionals (the array could be empty), so fall back to a default region instead of crashing.
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
