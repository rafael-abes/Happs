//
//  HappsAccessibilityTests.swift
//  Happs
//
//  Created by Rafa Abes on 10/31/26.
//


import XCTest
import UIKit
@testable import Happs

final class HappsAccessibilityTests: XCTestCase {

    // MARK: Contrast helper (WCAG 2.1 relative luminance)

    private func linear(_ c: CGFloat) -> CGFloat {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ color: UIColor, in traits: UITraitCollection) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func ratio(_ a: UIColor, _ b: UIColor, in traits: UITraitCollection) -> CGFloat {
        let la = luminance(a, in: traits), lb = luminance(b, in: traits)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func traits(dark: Bool, high: Bool) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: high ? .high : .normal)
        ])
    }

    private let lightBackground = UIColor.white
    private let darkBackground = UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)

    // MARK: Contrast

    func testGreenTextMeetsAAInEveryAppearance() {
        for high in [false, true] {
            let light = traits(dark: false, high: high)
            let dark = traits(dark: true, high: high)
            XCTAssertGreaterThanOrEqual(ratio(HappsPalette.greenText, lightBackground, in: light), 4.5, "light, high=\(high)")
            XCTAssertGreaterThanOrEqual(ratio(HappsPalette.greenText, darkBackground, in: dark), 4.5, "dark, high=\(high)")
        }
    }

    func testFillsMeetAAWithWhiteText() {
        for high in [false, true] {
            let t = traits(dark: false, high: high)
            XCTAssertGreaterThanOrEqual(ratio(HappsPalette.greenFill, .white, in: t), 4.5, "green, high=\(high)")
            XCTAssertGreaterThanOrEqual(ratio(HappsPalette.redFill, .white, in: t), 4.5, "red, high=\(high)")
        }
    }

    func testOldBrandGreenFailsOnWhite() {
        let brand = UIColor(red: 0.38, green: 0.68, blue: 0.31, alpha: 1)
        XCTAssertLessThan(ratio(brand, .white, in: traits(dark: false, high: false)), 4.5)
    }

    func testIncreasedContrastIsStrongerThanNormal() {
        let normal = ratio(HappsPalette.greenText, lightBackground, in: traits(dark: false, high: false))
        let high = ratio(HappsPalette.greenText, lightBackground, in: traits(dark: false, high: true))
        XCTAssertGreaterThan(high, normal)
    }

    // MARK: Status is never colour alone

    func testEveryStatusHasADistinctSymbol() {
        let symbols = UserStatus.allCases.map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, UserStatus.allCases.count)
        XCTAssertTrue(symbols.allSatisfy { !$0.isEmpty })
    }

    func testEveryAvatarHasASpokenName() {
        for symbol in AvatarSymbols.all {
            XCTAssertNotNil(AvatarSymbols.names[symbol], "\(symbol) has no spoken name")
        }
        XCTAssertEqual(AvatarSymbols.name(for: nil), "Person")
        XCTAssertEqual(AvatarSymbols.name(for: "unknown.symbol"), "Profile picture")
    }

    // MARK: VoiceOver wording

    func testUnreadNotificationSaysUnreadFirst() {
        let text = AccessibilityText.notificationRow(isRead: false, title: "Group invite", body: "Sam invited you", date: nil)
        XCTAssertEqual(text, "Unread. Group invite. Sam invited you")
    }

    func testReadNotificationDoesNotSayUnread() {
        let text = AccessibilityText.notificationRow(isRead: true, title: "Group invite", body: "Sam invited you", date: nil)
        XCTAssertFalse(text.contains("Unread"))
    }

    func testNotificationOmitsEmptyBody() {
        let text = AccessibilityText.notificationRow(isRead: true, title: "Hello", body: "", date: nil)
        XCTAssertEqual(text, "Hello")
    }

    func testFriendRowVariants() {
        XCTAssertEqual(AccessibilityText.friendRow(name: "Sam", status: "Busy", isVisible: true, isOnCampus: true), "Sam, on campus, Busy")
        XCTAssertEqual(AccessibilityText.friendRow(name: "Sam", status: "Busy", isVisible: true, isOnCampus: false), "Sam, Busy")
        XCTAssertEqual(AccessibilityText.friendRow(name: "Sam", status: "Busy", isVisible: false, isOnCampus: true), "Sam, hidden")
    }

    func testGroupsRowSaysInvitationsOrCount() {
        XCTAssertEqual(AccessibilityText.groupsRow(groupCount: 3, newInvitations: 0), "Groups, 3 groups")
        XCTAssertEqual(AccessibilityText.groupsRow(groupCount: 1, newInvitations: 0), "Groups, 1 group")
        XCTAssertEqual(AccessibilityText.groupsRow(groupCount: 3, newInvitations: 1), "Groups, 1 new invitation")
        XCTAssertEqual(AccessibilityText.groupsRow(groupCount: 3, newInvitations: 2), "Groups, 2 new invitations")
    }

    func testHappRowJoinsAllParts() {
        let text = AccessibilityText.happRow(title: "Badminton", badge: "Joined", category: "Sport", location: "Sports Hall", time: "5:56 PM to 7:00 PM")
        XCTAssertEqual(text, "Badminton, Joined, Sport, Sports Hall, 5:56 PM to 7:00 PM")
    }

    func testHappRowSkipsMissingBadgeAndLocation() {
        let text = AccessibilityText.happRow(title: "Badminton", badge: nil, category: "Sport", location: "", time: "5 PM")
        XCTAssertEqual(text, "Badminton, Sport, 5 PM")
    }

    func testPinLabels() {
        XCTAssertEqual(AccessibilityText.happPin(title: "Badminton", category: "Sport", goingCount: 3), "Badminton, Sport, 3 going")
        XCTAssertEqual(AccessibilityText.friendPin(name: "Sam", status: "Busy"), "Sam, Busy, on the map")
    }

    func testRecapPhotoUsesCaptionWhenPresent() {
        XCTAssertEqual(AccessibilityText.recapPhoto(author: "Rafa", caption: "Great game"), "Photo by Rafa. Great game")
        XCTAssertEqual(AccessibilityText.recapPhoto(author: "Rafa", caption: ""), "Photo by Rafa")
        XCTAssertEqual(AccessibilityText.photoPosition(index: 2, total: 5), "Photo 2 of 5")
    }

    // MARK: Dictation

    func testDictationFixTurnsAppIntoHapp() {
        XCTAssertEqual(HappSpeechFixer.fix("create an app tomorrow"), "create a Happ tomorrow")
        XCTAssertEqual(HappSpeechFixer.fix("two apps"), "two Happs")
    }

    func testDictationIsAddedAfterExistingText() {
        XCTAssertEqual(HappSpeechFixer.joined(base: "Pizza", transcript: "with friends", fixesHapp: false), "Pizza with friends")
        XCTAssertEqual(HappSpeechFixer.joined(base: "", transcript: "an app", fixesHapp: true), "a Happ")
    }
}