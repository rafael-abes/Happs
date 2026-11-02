//
//  AccessibilityAuditTests.swift
//  Happs
//
//  Created by Rafa Abes on 10/31/26.
//


import XCTest

final class AccessibilityAuditTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(largeText: Bool, dark: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if dark {
            app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        }
        app.launch()
        return app
    }

    func testLandingScreenPassesAuditAtDefaultSize() throws {
        let app = launch(largeText: false, dark: false)
        try app.performAccessibilityAudit()
    }

    func testLandingScreenPassesAuditAtLargestTextSize() throws {
        let app = launch(largeText: true, dark: false)
        try app.performAccessibilityAudit()
    }

    func testLandingScreenPassesAuditInDarkMode() throws {
        let app = launch(largeText: false, dark: true)
        try app.performAccessibilityAudit()
    }

    func testLogInFormPassesAudit() throws {
        let app = launch(largeText: true, dark: false)
        let logIn = app.buttons["Log in"]
        XCTAssertTrue(logIn.waitForExistence(timeout: 5), "Log in button should be reachable by its label")
        logIn.tap()
        XCTAssertTrue(app.textFields["Email address"].waitForExistence(timeout: 5), "Email field should be reachable by its label")
        XCTAssertTrue(app.secureTextFields["Password"].exists, "Password field should be reachable by its label")
        try app.performAccessibilityAudit()
    }

    func testEveryFormButtonHasALabel() throws {
        let app = launch(largeText: false, dark: false)
        app.buttons["Sign Up"].tap()
        for button in app.buttons.allElementsBoundByIndex {
            XCTAssertFalse(button.label.isEmpty, "A button on the sign up form has no VoiceOver label")
        }
    }
}