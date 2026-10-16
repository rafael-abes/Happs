//
//  HappsTests.swift
//  HappsTests
//
//  Created by Rafa Abes on 9/10/26.
//

import Testing
import Foundation
import CoreLocation
import MapKit
import SwiftUI
@testable import Happs

private let baseStart = Date(timeIntervalSince1970: 1_800_000_000)

private func makeHapp(
    start: Date = baseStart,
    end: Date? = nil,
    participants: [String] = ["host"],
    invited: [String]? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil
) -> Happ {
    Happ(
        title: "Badminton",
        details: "",
        location: "Monash Sport",
        category: .sport,
        participantIDs: participants,
        creatorID: "host",
        creatorName: "Host",
        startTime: start,
        endTime: end,
        latitude: latitude,
        longitude: longitude,
        invitedIDs: invited
    )
}

struct SearchKeyTests {
    @Test func ignoresCase() {
        #expect(UserSearchEntry.searchKey(for: "Papoi") == UserSearchEntry.searchKey(for: "papoi"))
        #expect(UserSearchEntry.searchKey(for: "PAPOI") == "papoi")
    }
    
    @Test func trimsWhitespace() {
        #expect(UserSearchEntry.searchKey(for: "  Papoi \n") == "papoi")
    }
    
    @Test func foldsAccents() {
        #expect(UserSearchEntry.searchKey(for: "José") == "jose")
    }
    
    @Test func blankInputGivesEmptyKey() {
        #expect(UserSearchEntry.searchKey(for: "   ").isEmpty)
    }
}

struct HappTimingTests {
    @Test func defaultEndIsThreeHoursAfterStart() {
        let happ = makeHapp()
        #expect(happ.effectiveEndTime == baseStart.addingTimeInterval(3 * 3600))
    }
    
    @Test func explicitEndWins() {
        let end = baseStart.addingTimeInterval(1800)
        #expect(makeHapp(end: end).effectiveEndTime == end)
    }
    
    @Test func hasEndedFlipsExactlyAtEnd() {
        let end = baseStart.addingTimeInterval(3600)
        let happ = makeHapp(end: end)
        #expect(happ.hasEnded(at: end.addingTimeInterval(-1)) == false)
        #expect(happ.hasEnded(at: end) == true)
    }
    
    @Test func activeWindowStartsOneHourBeforeAndStopsAtEnd() {
        let end = baseStart.addingTimeInterval(3600)
        let happ = makeHapp(end: end)
        #expect(happ.isActive(at: baseStart.addingTimeInterval(-1800)) == true)
        #expect(happ.isActive(at: baseStart.addingTimeInterval(-7200)) == false)
        #expect(happ.isActive(at: end.addingTimeInterval(-1)) == true)
        #expect(happ.isActive(at: end) == false)
    }
    
    @Test func timeRangeTextShowsBothEnds() {
        #expect(makeHapp(end: baseStart.addingTimeInterval(3600)).timeRangeText.contains(" to "))
    }
}

struct HappMembershipTests {
    @Test func participantAndInviteChecks() {
        let happ = makeHapp(participants: ["host", "a"], invited: ["b"])
        #expect(happ.containsParticipant("a"))
        #expect(!happ.containsParticipant("b"))
        #expect(happ.isInvited("b"))
        #expect(!happ.isInvited("a"))
    }
    
    @Test func missingInvitesMeansNobodyInvited() {
        #expect(makeHapp(invited: nil).isInvited("anyone") == false)
    }
    
    @Test func coordinateNeedsBothValues() {
        #expect(makeHapp(latitude: -37.91, longitude: nil).coordinate == nil)
        #expect(makeHapp(latitude: -37.91, longitude: 145.13).coordinate != nil)
    }
}

@MainActor
struct CampusGeofenceTests {
    private var centre: CLLocationCoordinate2D {
        let points = LocationService.campusBoundary
        let count = Double(points.count)
        return CLLocationCoordinate2D(
            latitude: points.map(\.latitude).reduce(0, +) / count,
            longitude: points.map(\.longitude).reduce(0, +) / count
        )
    }
    
    @Test func boundaryHasFourCorners() {
        #expect(LocationService.campusBoundary.count == 4)
    }
    
    @Test func centreIsInside() {
        #expect(LocationService.isInside(centre, polygon: LocationService.campusBoundary))
    }
    
    @Test func farAwayIsOutside() {
        let cbd = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
        #expect(!LocationService.isInside(cbd, polygon: LocationService.campusBoundary))
    }
    
    @Test func justBeyondEachSideIsOutside() {
        let north = CLLocationCoordinate2D(latitude: -37.90, longitude: centre.longitude)
        let south = CLLocationCoordinate2D(latitude: -37.93, longitude: centre.longitude)
        let east = CLLocationCoordinate2D(latitude: centre.latitude, longitude: 145.16)
        let west = CLLocationCoordinate2D(latitude: centre.latitude, longitude: 145.10)
        for point in [north, south, east, west] {
            #expect(!LocationService.isInside(point, polygon: LocationService.campusBoundary))
        }
    }
}

struct ModelAndMappingTests {
    @Test func statusRawValuesMatchStoredStrings() {
        #expect(UserStatus.allCases.map(\.rawValue) == ["Available", "In Class", "Busy", "Do Not Disturb"])
    }
    
    @Test func statusColours() {
        #expect(UserStatus.available.color == .green)
        #expect(UserStatus.busy.color == .red)
        #expect(UserStatus.doNotDisturb.color == .gray)
    }
    
    @Test func errorMessages() {
        #expect(AppError.invalidForm("Nope").errorDescription == "Nope")
        #expect(AppError.happNotFound.errorDescription == "This happ no longer exists.")
    }
    
    @Test func groupStartsWithOwnerAsMemberAndOthersInvited() {
        let group = FriendGroup(name: "Crew", ownerID: "o", memberIDs: ["o"], invitedIDs: ["a", "b"])
        #expect(group.memberIDs == ["o"])
        #expect(group.invitedIDs == ["a", "b"])
    }
    
    @Test func avatarSymbolsAreUniqueAndIncludeFallback() {
        #expect(AvatarSymbols.all.contains(AvatarSymbols.fallback))
        #expect(Set(AvatarSymbols.all).count == AvatarSymbols.all.count)
    }
    
    @Test func notificationSymbols() {
        #expect(NotificationKind.friendRequest.symbolName == "person.badge.plus")
        #expect(NotificationKind.happCancelled.symbolName == "xmark.circle.fill")
    }
    
    @Test func categorySymbolsAndFilters() {
        #expect(HappCategory.sport.symbolName == "figure.run")
        #expect(HappCategory.happs.pointOfInterestFilter == nil)
        #expect(HappCategory.food.pointOfInterestFilter != nil)
    }
}
