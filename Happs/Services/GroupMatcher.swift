//
//  GroupMatcher.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
import Foundation

/// Matches a phrase like "the study crew" to one of the user's friend groups, locally.
/// Group names never leave the device.
nonisolated struct GroupCandidate: Equatable {
    let id: String
    let name: String
}

nonisolated enum GroupMatcher {
    private static let stopWords: Set<String> = [
        "the", "a", "my", "our", "group", "with", "and", "for", "to", "invite", "of"
    ]

    /// Returns the single best match, or nil when nothing overlaps or two groups tie.
    static func match(_ phrase: String?, in groups: [GroupCandidate]) -> GroupCandidate? {
        guard let phrase else { return nil }
        let wanted = tokens(phrase)
        guard !wanted.isEmpty else { return nil }

        var best: [GroupCandidate] = []
        var bestScore = 0
        for group in groups {
            let score = wanted.intersection(tokens(group.name)).count
            if score > bestScore {
                bestScore = score
                best = [group]
            } else if score == bestScore, score > 0 {
                best.append(group)
            }
        }
        return (bestScore > 0 && best.count == 1) ? best[0] : nil
    }

    static func tokens(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { !$0.isEmpty && !stopWords.contains($0) })
    }
}
