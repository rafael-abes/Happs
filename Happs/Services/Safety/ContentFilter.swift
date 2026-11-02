//
//  ContentFilter.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


import Foundation

nonisolated enum ContentFilter {

    enum Verdict: Equatable {
        case allowed
        case blocked(category: String)
    }

    static let hiddenPlaceholder = "Hidden: this text breaks the community rules."

    // Common swear words, matched anywhere inside a word.
    private static let swearWords = [
        "fuck", "shit", "bitch", "cunt", "dick", "cock", "pussy"
    ]

    private static let lookAlikes: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a",
        "5": "s", "7": "t", "@": "a", "$": "s"
    ]

    // MARK: Public API

    static func check(_ text: String) -> Verdict {
        let tokens = tokenise(text)

        for token in tokens {
            if swearWords.contains(where: { token.contains($0) }) {
                return .blocked(category: "profanity")
            }
        }

        for joined in spacedLetterRuns(in: tokens) {
            if swearWords.contains(where: { joined.contains($0) }) {
                return .blocked(category: "profanity")
            }
        }

        return .allowed
    }

    static func isAllowed(_ text: String) -> Bool {
        check(text) == .allowed
    }

    static func validate(_ text: String, field: String) throws {
        if case .blocked = check(text) {
            throw AppError.invalidForm(
                "Your \(field) includes language that isn't allowed in Happs. Please change it and try again."
            )
        }
    }

    static func displayText(_ text: String) -> String {
        isAllowed(text) ? text : hiddenPlaceholder
    }

    // MARK: Internals

    static func tokenise(_ text: String) -> [String] {
        let folded = text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)

        let words = folded.split {
            !($0.isLetter || $0.isNumber || $0 == "@" || $0 == "$")
        }

        return words.map {
            collapse(mapLookAlikes(String($0)))
        }.filter { !$0.isEmpty }
    }

    private static func mapLookAlikes(_ word: String) -> String {
        String(word.map { lookAlikes[$0] ?? $0 })
    }

    // Three or more repeated letters are reduced to one.
    private static func collapse(_ word: String) -> String {
        var result = ""
        var run = 0
        var previous: Character?

        for character in word {
            if character == previous {
                run += 1
            } else {
                if run >= 3, let previous {
                    result.append(previous)
                } else if run > 0, let previous {
                    result.append(String(repeating: previous, count: run))
                }

                run = 1
                previous = character
            }
        }

        if let previous {
            if run >= 3 {
                result.append(previous)
            } else {
                result.append(String(repeating: previous, count: run))
            }
        }

        return result
    }

    // Joins runs of three or more single letters ("f u c k" becomes "fuck").
    private static func spacedLetterRuns(in tokens: [String]) -> [String] {
        var runs: [String] = []
        var current = ""
        var count = 0

        for token in tokens {
            if token.count == 1 {
                current += token
                count += 1
            } else {
                if count >= 3 {
                    runs.append(current)
                }

                current = ""
                count = 0
            }
        }

        if count >= 3 {
            runs.append(current)
        }

        return runs
    }
}
