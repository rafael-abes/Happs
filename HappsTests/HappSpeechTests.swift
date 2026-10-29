//
//  HappSpeechTests.swift
//  Happs
//
//  Created by Rafa Abes on 10/28/26.
//


import XCTest
@testable import Happs
 
/// Tests for the speech fix: the recogniser kept hearing "Happ" as "app".
/// Two defences were added and both are tested here:
///   1. Hint words given to the recogniser (SpeechRecognizer.contextualStrings).
///   2. A correction step on the transcript (HappSpeechFixer), switched on only for the
///      assistant and search boxes.
/// The microphone itself cannot be unit tested, so these tests feed the recogniser's
/// typical wrong answers straight into the correction code.
final class HappSpeechTests: XCTestCase {
 
    // MARK: SPH-01 to SPH-04: the wrong transcripts are corrected
 
    func testSPH01_SingularAppBecomesHapp() {
        XCTAssertEqual(HappSpeechFixer.fix("app"), "Happ")
        XCTAssertEqual(HappSpeechFixer.fix("join the app tonight"), "join the Happ tonight")
        XCTAssertEqual(HappSpeechFixer.fix("App"), "Happ")
    }
 
    func testSPH02_PluralAppsBecomesHapps() {
        XCTAssertEqual(HappSpeechFixer.fix("apps"), "Happs")
        XCTAssertEqual(HappSpeechFixer.fix("show me apps near the library"), "show me Happs near the library")
    }
 
    func testSPH03_ArticleAgreesWithTheCorrectedWord() {
        // The recogniser writes "an app"; once it is "Happ" the article must be "a".
        XCTAssertEqual(HappSpeechFixer.fix("create an app tomorrow at 3pm"), "create a Happ tomorrow at 3pm")
        XCTAssertEqual(HappSpeechFixer.fix("An app for study"), "A Happ for study")
        XCTAssertEqual(HappSpeechFixer.fix("an apps"), "a Happs")
    }
 
    func testSPH04_FullDictatedSentenceFromTheAssistant() {
        let heard = "I want to create an app with my friends at Matheson library tomorrow at 3 PM"
        let expected = "I want to create a Happ with my friends at Matheson library tomorrow at 3 PM"
        XCTAssertEqual(HappSpeechFixer.fix(heard), expected)
    }
 
    // MARK: SPH-05 to SPH-08: other words are left alone
 
    func testSPH05_WordsThatMerelyContainAppAreUntouched() {
        for word in ["apple", "application", "happy", "happen", "whatsapp", "WhatsApp", "approve", "snapshot"] {
            XCTAssertEqual(HappSpeechFixer.fix(word), word, "\(word) must not change")
        }
        XCTAssertEqual(HappSpeechFixer.fix("apple pie and happy hour"), "apple pie and happy hour")
    }
 
    func testSPH06_AlreadyCorrectTextIsUnchanged() {
        XCTAssertEqual(HappSpeechFixer.fix("Happ"), "Happ")
        XCTAssertEqual(HappSpeechFixer.fix("happ"), "happ")
        XCTAssertEqual(HappSpeechFixer.fix("Happs"), "Happs")
        XCTAssertEqual(HappSpeechFixer.fix("a Happ tonight"), "a Happ tonight")
    }
 
    func testSPH07_FixingTwiceGivesTheSameResult() {
        let samples = ["create an app", "apps and more apps", "Happ", "apple", ""]
        for text in samples {
            let once = HappSpeechFixer.fix(text)
            XCTAssertEqual(HappSpeechFixer.fix(once), once, "fix must be idempotent for: \(text)")
        }
    }
 
    func testSPH08_EmptyAndWhitespaceAreSafe() {
        XCTAssertEqual(HappSpeechFixer.fix(""), "")
        XCTAssertEqual(HappSpeechFixer.fix("   "), "   ")
    }
 
    // MARK: SPH-09 to SPH-11: punctuation and repeats
 
    func testSPH09_PunctuationAndPossessivesAreHandled() {
        XCTAssertEqual(HappSpeechFixer.fix("app."), "Happ.")
        XCTAssertEqual(HappSpeechFixer.fix("(app)"), "(Happ)")
        XCTAssertEqual(HappSpeechFixer.fix("the app's location"), "the Happ's location")
        XCTAssertEqual(HappSpeechFixer.fix("apps, then apps!"), "Happs, then Happs!")
    }
 
    func testSPH10_EveryOccurrenceIsFixed() {
        XCTAssertEqual(HappSpeechFixer.fix("app app app"), "Happ Happ Happ")
    }
 
    func testSPH11_NewlinesAndTabsCountAsWordBreaks() {
        XCTAssertEqual(HappSpeechFixer.fix("one\napp\ttwo"), "one\nHapp\ttwo")
    }
 
    // MARK: SPH-12: a documented limit
 
    func testSPH12_KnownTradeoffRealAppsAlsoChange() {
        // The fix cannot tell "app" the software from a misheard "Happ". That is why it is
        // OFF for free text (titles, notes) and ON only for the assistant and search.
        XCTAssertEqual(HappSpeechFixer.fix("download the app store"), "download the Happ store")
    }
 
    // MARK: SPH-13 to SPH-16: how dictation is merged into a field
 
    func testSPH13_FixIsAppliedOnlyWhenSwitchedOn() {
        XCTAssertEqual(HappSpeechFixer.joined(base: "", transcript: "create an app", fixesHapp: true), "create a Happ")
        XCTAssertEqual(HappSpeechFixer.joined(base: "", transcript: "create an app", fixesHapp: false), "create an app",
                       "Free-text fields such as titles must keep exactly what was heard")
    }
 
    func testSPH14_DictationIsAppendedWithOneSpace() {
        XCTAssertEqual(HappSpeechFixer.joined(base: "Study", transcript: "at the library", fixesHapp: false),
                       "Study at the library")
        XCTAssertEqual(HappSpeechFixer.joined(base: "Study ", transcript: "at the library", fixesHapp: false),
                       "Study at the library", "No double space when the field already ends in one")
    }
 
    func testSPH15_EmptyFieldGetsNoLeadingSpace() {
        XCTAssertEqual(HappSpeechFixer.joined(base: "", transcript: "apps", fixesHapp: true), "Happs")
    }
 
    func testSPH16_ExistingTextIsNeverCorrected() {
        // Only the newly dictated words are corrected, never text the user typed earlier.
        XCTAssertEqual(HappSpeechFixer.joined(base: "my app idea", transcript: "and an app", fixesHapp: true),
                       "my app idea and a Happ")
    }
 
    // MARK: SPH-17 and SPH-18: hints given to the recogniser
 
    func testSPH17_RecogniserIsToldToExpectHapp() {
        XCTAssertTrue(SpeechRecognizer.contextualStrings.contains("Happ"))
        XCTAssertTrue(SpeechRecognizer.contextualStrings.contains("Happs"))
    }
 
    func testSPH18_HintListHasNoBlanksOrDuplicates() {
        let hints = SpeechRecognizer.contextualStrings
        XCTAssertFalse(hints.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        XCTAssertEqual(hints.count, Set(hints).count)
    }
}