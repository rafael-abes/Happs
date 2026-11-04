//
//  GroupMatcher.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
// CODE OVERVIEW
// Resolves a free-text group phrase (for example from the AI intent parser) to one of the
// user's own friend groups. It is a pure, stateless function in a caseless enum, so it is easy
// to unit test and has no side effects. Matching is done on-device by comparing word sets, so
// group names are never sent to the AI service (the parser only returns the spoken phrase).
// A match is only returned when exactly one group has the best score, otherwise nil, so the
// caller can ask the user instead of guessing the wrong group.
//
import Foundation

// The types here are marked nonisolated so they can be used from any thread
// (assumed reason: the project may default types to the main actor).
/// Matches a phrase like "the study crew" to one of the user's friend groups, locally.
/// Group names never leave the device.
nonisolated struct GroupCandidate: Equatable {
    /// Firestore document id of the group.
    let id: String
    /// Display name the user gave the group.
    let name: String
}

/// Namespace for the matching logic. An enum with no cases cannot be instantiated.
nonisolated enum GroupMatcher {
    /// Filler words ignored when comparing, so "the" or "group" alone never counts as an overlap.
    private static let stopWords: Set<String> = [
        "the", "a", "my", "our", "group", "with", "and", "for", "to", "invite", "of"
    ]

    /// Returns the single best match, or nil when nothing overlaps or two groups tie.
    static func match(_ phrase: String?, in groups: [GroupCandidate]) -> GroupCandidate? {
        guard let phrase else { return nil }
        let wanted = tokens(phrase)
        guard !wanted.isEmpty else { return nil }

        // Keep every group sharing the top score so a tie can be detected afterwards.
        var best: [GroupCandidate] = []
        var bestScore = 0
        for group in groups {
            // Score = how many meaningful words the phrase and the group name share.
            let score = wanted.intersection(tokens(group.name)).count
            if score > bestScore {
                bestScore = score
                best = [group]
            } else if score == bestScore, score > 0 {
                best.append(group)
            }
        }
        // Ambiguous (tie) or no overlap: return nil rather than pick one at random.
        return (bestScore > 0 && best.count == 1) ? best[0] : nil
    }

    /// Splits text into a set of lowercase, accent-free words with stop words removed.
    /// A Set is used because only overlap matters, not order or repeats.
    static func tokens(_ text: String) -> Set<String> {
        // Folding makes "Café" and "cafe" compare equal.
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { !$0.isEmpty && !stopWords.contains($0) })
    }
}
