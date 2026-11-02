//
//  HappsSafetyTests.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


import XCTest
@testable import Happs

@MainActor
final class HappsSafetyTests: XCTestCase {

    // MARK: ContentFilter

    func testBlocksStrongTermsAndVariants() {
        for text in ["what the fuck", "FUCK", "fuuuuck", "f u c k", "f.u.c.k", "sh1t", "$hit", "you are a bitch"] {
            XCTAssertNotEqual(ContentFilter.check(text), .allowed, text)
        }
    }

    func testBlocksThreatPhrases() {
        XCTAssertNotEqual(ContentFilter.check("go kill yourself"), .allowed)
        XCTAssertNotEqual(ContentFilter.check("I will find you"), .allowed)
    }

    func testAllowsInnocentWords() {
        for text in ["Hancock Hall study session", "grape juice social", "pedometer challenge",
                     "Scunthorpe United watch party", "shiitake cooking class", "Assessment help",
                     "Study jam at the library", "Basketball 3v3 at 5pm", "Mocktail mixology night"] {
            XCTAssertEqual(ContentFilter.check(text), .allowed, text)
        }
    }

    func testEmptyAndWhitespaceAreAllowed() {
        XCTAssertEqual(ContentFilter.check(""), .allowed)
        XCTAssertEqual(ContentFilter.check("   "), .allowed)
    }

    func testValidateThrowsWithFieldName() {
        XCTAssertThrowsError(try ContentFilter.validate("fuck this", field: "title")) { error in
            XCTAssertTrue(error.localizedDescription.contains("title"))
        }
        XCTAssertNoThrow(try ContentFilter.validate("Movie night", field: "title"))
    }

    func testDisplayTextReplacesBadTextOnly() {
        XCTAssertEqual(ContentFilter.displayText("Nice photo"), "Nice photo")
        XCTAssertEqual(ContentFilter.displayText("fuck"), ContentFilter.hiddenPlaceholder)
    }

    // MARK: Reports

    func testReportPayload() {
        let target = ReportTarget(
            kind: .photo, targetID: "h1_u1_abc.jpg", happID: "h1", offenderID: "u1",
            offenderName: "Sam", summary: String(repeating: "x", count: 300), hideID: "h1_u1_abc.jpg"
        )
        let long = "  " + String(repeating: "a", count: 600) + "  "
        let data = target.payload(reporterID: "me", reason: .spam, details: long)
        XCTAssertEqual(data["reporterID"] as? String, "me")
        XCTAssertEqual(data["offenderID"] as? String, "u1")
        XCTAssertEqual(data["reason"] as? String, "Spam or scam")
        XCTAssertEqual(data["status"] as? String, "open")
        XCTAssertEqual(data["happID"] as? String, "h1")
        XCTAssertEqual((data["summary"] as? String)?.count, 200)
        XCTAssertEqual((data["details"] as? String)?.count, 500)
    }

    func testReportWithoutHappOmitsHappID() {
        let target = ReportTarget(kind: .profile, targetID: "u1", happID: nil, offenderID: "u1",
                                  offenderName: "Sam", summary: "", hideID: nil)
        XCTAssertNil(target.payload(reporterID: "me", reason: .other, details: "")["happID"])
    }

    func testSafeIDRemovesSlashes() {
        XCTAssertEqual(ReportTarget.safeID("a/b/c.jpg"), "a_b_c.jpg")
    }

    // MARK: Gemini consent

    func testConsentLifecycle() {
        let defaults = UserDefaults(suiteName: "HappsSafetyTests")!
        defaults.removePersistentDomain(forName: "HappsSafetyTests")
        XCTAssertFalse(AIConsent.hasConsented(userID: "a", defaults: defaults))
        AIConsent.setConsent(true, userID: "a", defaults: defaults)
        XCTAssertTrue(AIConsent.hasConsented(userID: "a", defaults: defaults))
        XCTAssertFalse(AIConsent.hasConsented(userID: "b", defaults: defaults), "per account")
        AIConsent.setConsent(false, userID: "a", defaults: defaults)
        XCTAssertFalse(AIConsent.hasConsented(userID: "a", defaults: defaults))
    }

    func testOlderConsentVersionAsksAgain() {
        let defaults = UserDefaults(suiteName: "HappsSafetyTests2")!
        defaults.removePersistentDomain(forName: "HappsSafetyTests2")
        defaults.set(AIConsent.currentVersion - 1, forKey: AIConsent.key(for: "a"))
        XCTAssertFalse(AIConsent.hasConsented(userID: "a", defaults: defaults))
    }

    // MARK: FOMO notifications

    func testRecapNotificationAudience() {
        let audience = RecapAudience(
            happTitle: "Study jam",
            attendeeIDs: ["poster", "a", "b"],
            friendIDs: ["a", "c", "d"]
        )
        let drafts = RecapNotifications.drafts(for: audience, authorID: "poster", authorName: "Sam", photoCount: 3)
        let posted = drafts.filter { $0.kind == .recapPosted }.map(\.recipientID)
        let missed = drafts.filter { $0.kind == .recapMissed }.map(\.recipientID)
        XCTAssertEqual(Set(posted), ["a", "b"])
        XCTAssertEqual(Set(missed), ["c", "d"])
        XCTAssertFalse(drafts.contains { $0.recipientID == "poster" })
        XCTAssertEqual(drafts.count, 4, "nobody is told twice")
        XCTAssertTrue(drafts.first { $0.kind == .recapPosted }!.body.contains("3 photos"))
    }

    func testNoPhotosNoNotifications() {
        let audience = RecapAudience(happTitle: "X", attendeeIDs: ["a"], friendIDs: ["b"])
        XCTAssertTrue(RecapNotifications.drafts(for: audience, authorID: "p", authorName: "S", photoCount: 0).isEmpty)
    }

    func testSinglePhotoWording() {
        let audience = RecapAudience(happTitle: "X", attendeeIDs: ["a"], friendIDs: [])
        let drafts = RecapNotifications.drafts(for: audience, authorID: "p", authorName: "S", photoCount: 1)
        XCTAssertTrue(drafts[0].body.contains("a photo"))
    }

    func testNewKindsHaveSymbolAndAreNotNegative() {
        for kind in [NotificationKind.recapPosted, .recapMissed] {
            XCTAssertFalse(kind.symbolName.isEmpty)
            XCTAssertFalse(kind.isNegative)
        }
    }

    func testReminderPlanOnlyFutureJoinedHapps() {
        let now = Date()
        func happ(_ title: String, joined: Bool, start: TimeInterval) -> Happ {
            Happ(title: title, details: "", location: "L", category: .study,
                         participantIDs: joined ? ["me"] : ["other"], creatorID: "other",
                         creatorName: "O", startTime: now.addingTimeInterval(start),
                 endTime: now.addingTimeInterval(start + 3600))
        }
        let plan = RecapReminders.plan(
            happs: [happ("future", joined: true, start: 3600),
                    happ("notJoined", joined: false, start: 3600),
                    happ("past", joined: true, start: -86_400)],
            userID: "me", now: now
        )
        XCTAssertEqual(plan.map(\.title), ["future"])
        XCTAssertEqual(plan[0].fireDate.timeIntervalSince(now), 3600 + 3600 + RecapReminders.delay, accuracy: 1)
    }
}