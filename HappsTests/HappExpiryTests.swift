//
//  HappExpiryTests.swift
//  Happs
//
//  Created by Rafa Abes on 10/16/26.
//
import Testing
import Foundation
@testable import Happs

private let testStart = Date(timeIntervalSince1970: 1_800_000_000)

private func makeTestHapp(
    end: Date? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil,
    isOffCampus: Bool? = nil
) -> Happ {
    Happ(
        title: "Sausage sizzle",
        details: "",
        location: "Library lawn",
        category: .food,
        participantIDs: ["host"],
        creatorID: "host",
        creatorName: "Host",
        startTime: testStart,
        endTime: end,
        latitude: latitude,
        longitude: longitude,
        isOffCampus: isOffCampus
    )
}

struct OpenEndedHappTests {
    @Test func missingEndTimeIsOpenEnded() {
        let happ = makeTestHapp()
        #expect(happ.hasEndTime == false)
        #expect(happ.effectiveEndTime == testStart.addingTimeInterval(Happ.defaultDuration))
        #expect(happ.timeRangeText.contains("open-ended"))
    }
    
    @Test func openEndedStillExpires() {
        let happ = makeTestHapp()
        #expect(happ.hasEnded(at: testStart.addingTimeInterval(Happ.defaultDuration - 1)) == false)
        #expect(happ.hasEnded(at: testStart.addingTimeInterval(Happ.defaultDuration)) == true)
    }
    
    @Test func boundariesCoverLeadInAndEnd() {
        let end = testStart.addingTimeInterval(7200)
        let boundaries = [makeTestHapp(end: end)].clockBoundaries
        #expect(boundaries.contains(testStart.addingTimeInterval(-3600)))
        #expect(boundaries.contains(end))
    }
}

struct OffCampusMapTests {
    @Test func pinnedHappShowsOnMap() {
        #expect(makeTestHapp(latitude: -37.91, longitude: 145.13).showsOnMap == true)
    }
    
    @Test func offCampusFlagKeepsItOffTheMap() {
        #expect(makeTestHapp(latitude: -37.91, longitude: 145.13, isOffCampus: true).showsOnMap == false)
    }
    
    @Test func noPinMeansNoMarker() {
        #expect(makeTestHapp().showsOnMap == false)
    }
}
