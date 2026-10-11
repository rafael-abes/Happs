//
//  CampusLockedView.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//
import SwiftUI
import MapKit

enum CampusAccess {
    case locating, noPermission, outside, inside
}

extension LocationService {
    var campusAccess: CampusAccess {
        switch authorizationStatus {
        case .denied, .restricted:
            return .noPermission
        default:
            break
        }
        guard currentCoordinate != nil else { return .locating }
        return isInsideCampus ? .inside : .outside
    }
}

struct CampusLockedView: View {
    let access: CampusAccess
    let happs: [Happ]
    
    private var activeCount: Int {
        happs.filter { $0.isActiveNow }.count
    }
    
    private var headline: String {
        if access == .locating { return "Finding your location" }
        switch activeCount {
        case 0: return "No happs active right now"
        case 1: return "1 happ active now"
        default: return "\(activeCount) happs active now"
        }
    }
    
    private var detail: String {
        switch access {
        case .locating: "Hang tight while we check whether you're on campus."
        case .noPermission: "Turn on location for Happs in Settings to see what's happening on campus."
        case .outside, .inside: "Head to campus to see where everyone is and join in."
        }
    }
    
    var body: some View {
        ZStack {
            blurredCampus
            card
        }
    }
    
    private var blurredCampus: some View {
        Map(initialPosition: .region(LocationService.campusRegion), interactionModes: []) {
            MapPolygon(coordinates: LocationService.campusBoundary)
                .foregroundStyle(.green.opacity(0.25))
                .stroke(.green, lineWidth: 2)
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .blur(radius: 9)
        .allowsHitTesting(false)
        .clipped()
    }
    
    private var card: some View {
        VStack(spacing: 12) {
            if access == .locating {
                ProgressView()
            } else {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.happsGreen)
            }
            Text(headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(32)
    }
}
