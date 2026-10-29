//
//  GoogleUserMapTests.swift
//  Happs
//
//  Created by Rafa Abes on 10/28/26.
//


import XCTest
import CoreLocation
import FirebaseFirestore
@testable import Happs
 
/// Regression tests for: "Google sign-in users did not appear on friends' maps".
///
/// Most likely cause (never isolated for certain): older Google profiles were missing
/// `status`, `isVisible` or `friendIDs`. Strict decoding dropped those profiles, so the friend
/// never reached the map. These tests prove the tolerant decoding that fixed it, plus the
/// campus geometry that decides who is "on campus".
///
/// These call `UserProfile.tolerant(id:data:)`, the fallback path of `tolerant(from:)`.
/// It is the code that runs when strict decoding fails, which is what happened to old
/// Google profiles. (`tolerant(from:)` needs a Firestore snapshot, so it cannot be built here.)
@MainActor
final class GoogleUserMapTests: XCTestCase {
 
    private func decodeProfile(id: String = "google-user", _ data: [String: Any]) -> UserProfile? {
        UserProfile.tolerant(id: id, data: data)
    }
 
    // What an old Google profile looked like: name and email only.
    private let bareGoogleProfile: [String: Any] = [
        "displayName": "Google User",
        "email": "google.user@gmail.com"
    ]
 
    // MARK: Decoding old and incomplete Google profiles
 
    func testBareGoogleProfileStillDecodes() throws {
        let profile = try XCTUnwrap(decodeProfile(bareGoogleProfile),
                                    "A profile with only name and email must not be dropped")
        XCTAssertEqual(profile.displayName, "Google User")
    }
 
    func testMissingStatusDefaultsToAvailable() throws {
        let profile = try XCTUnwrap(decodeProfile(bareGoogleProfile))
        XCTAssertEqual(profile.status, .available)
    }
 
    func testMissingIsVisibleDefaultsToVisible() throws {
        let profile = try XCTUnwrap(decodeProfile(bareGoogleProfile))
        XCTAssertTrue(profile.isVisible, "Missing isVisible must default to true, matching the Firestore rule default")
    }
 
    func testMissingFriendIDsDefaultsToEmpty() throws {
        let profile = try XCTUnwrap(decodeProfile(bareGoogleProfile))
        XCTAssertEqual(profile.friendIDs, [])
    }
 
    func testMissingPresenceFieldsDecode() throws {
        let profile = try XCTUnwrap(decodeProfile(bareGoogleProfile))
        XCTAssertNil(profile.lastSeenAt)
    }
 
    func testEachFieldMissingOnItsOwnStillDecodes() {
        let full: [String: Any] = [
            "displayName": "Google User",
            "email": "google.user@gmail.com",
            "status": "Busy",
            "isVisible": true,
            "friendIDs": ["friend-1"]
        ]
        for key in ["status", "isVisible", "friendIDs"] {
            var data = full
            data.removeValue(forKey: key)
            XCTAssertNotNil(decodeProfile(data), "Profile must decode when \(key) is missing")
        }
    }
 
    // MARK: Wrong or unexpected values
 
    func testOldThreeStateStatusDoesNotDropProfile() throws {
        // Early builds used "Free". It no longer exists, so it must fall back, not fail.
        var data = bareGoogleProfile
        data["status"] = "Free"
        let profile = try XCTUnwrap(decodeProfile(data))
        XCTAssertEqual(profile.status, .available)
    }
 
    func testWrongTypesDoNotDropProfile() throws {
        var data = bareGoogleProfile
        data["isVisible"] = "yes"          // string instead of Bool
        data["friendIDs"] = NSNull()       // null instead of array
        data["status"] = 42                // number instead of string
        let profile = try XCTUnwrap(decodeProfile(data))
        XCTAssertTrue(profile.isVisible)
        XCTAssertEqual(profile.friendIDs, [])
        XCTAssertEqual(profile.status, .available)
    }
 
    // MARK: Regression: complete profiles are unchanged
 
    func testCompleteProfileKeepsItsValues() throws {
        let data: [String: Any] = [
            "displayName": "Email User",
            "email": "email.user@example.com",
            "status": "Busy",
            "isVisible": false,
            "friendIDs": ["a", "b"]
        ]
        let profile = try XCTUnwrap(decodeProfile(id: "email-user", data))
        XCTAssertEqual(profile.status, .busy)
        XCTAssertFalse(profile.isVisible, "An explicit Invisible Mode setting must be respected, not overwritten by the default")
        XCTAssertEqual(profile.friendIDs, ["a", "b"])
    }
 
    // MARK: Identity and presence fields
 
    func testDocumentIDIsKept() throws {
        let profile = try XCTUnwrap(decodeProfile(id: "uid-123", bareGoogleProfile))
        XCTAssertEqual(profile.id, "uid-123", "The friend must keep their Firebase UID or their pin cannot be matched")
    }
 
    func testPresenceFieldsAreKeptWhenPresent() throws {
        let seen = Date(timeIntervalSince1970: 1_800_000_000)
        var data = bareGoogleProfile
        data["isOnCampus"] = true
        data["lastSeenAt"] = Timestamp(date: seen)
        let profile = try XCTUnwrap(decodeProfile(data))
        XCTAssertEqual(profile.isOnCampus, true)
        XCTAssertEqual(profile.lastSeenAt, seen)
    }
 
    func testMissingNameAndEmailGetSafeDefaults() throws {
        let profile = try XCTUnwrap(decodeProfile([:]))
        XCTAssertEqual(profile.displayName, "Happs User")
        XCTAssertEqual(profile.email, "")
    }
 
    // MARK: Freshness (a friend fades off the map after 180 seconds of silence)
 
    func testRecentHeartbeatIsFresh() {
        let now = Date()
        XCTAssertTrue(Freshness.isFresh(now.addingTimeInterval(-60), now: now, missingIsFresh: false))
        XCTAssertTrue(Freshness.isFresh(now.addingTimeInterval(-179), now: now, missingIsFresh: false))
    }
 
    func testOldHeartbeatIsStale() {
        let now = Date()
        XCTAssertFalse(Freshness.isFresh(now.addingTimeInterval(-180), now: now, missingIsFresh: false))
        XCTAssertFalse(Freshness.isFresh(now.addingTimeInterval(-600), now: now, missingIsFresh: true))
    }
 
    func testMissingTimestampFollowsTheFlag() {
        let now = Date()
        XCTAssertTrue(Freshness.isFresh(nil, now: now, missingIsFresh: true))
        XCTAssertFalse(Freshness.isFresh(nil, now: now, missingIsFresh: false))
    }
 
    func testClockSkewIntoTheFutureCountsAsFresh() {
        let now = Date()
        XCTAssertTrue(Freshness.isFresh(now.addingTimeInterval(30), now: now, missingIsFresh: false),
                      "A friend whose clock is slightly ahead must not disappear")
    }
 
    // MARK: Campus geometry (decides who counts as on campus)
 
    private let melbourneCBD = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
    private let campusMiddle = CLLocationCoordinate2D(latitude: -37.9110, longitude: 145.1346)
 
    func testCampusMiddleIsInsideCampus() {
        XCTAssertTrue(LocationService.isInside(campusMiddle, polygon: LocationService.campusBoundary))
    }
 
    func testMelbourneCBDIsOutsideCampus() {
        XCTAssertFalse(LocationService.isInside(melbourneCBD, polygon: LocationService.campusBoundary))
    }
 
    func testJustOutsideEachEdgeIsOutside() {
        // Points a little beyond the north, south, east and west limits of the polygon.
        let outside = [
            CLLocationCoordinate2D(latitude: -37.9000, longitude: 145.1346),
            CLLocationCoordinate2D(latitude: -37.9200, longitude: 145.1346),
            CLLocationCoordinate2D(latitude: -37.9110, longitude: 145.1500),
            CLLocationCoordinate2D(latitude: -37.9110, longitude: 145.1200)
        ]
        for point in outside {
            XCTAssertFalse(LocationService.isInside(point, polygon: LocationService.campusBoundary),
                           "\(point.latitude), \(point.longitude) should be off campus")
        }
    }
}
