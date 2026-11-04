//
//  AccessibilityText.swift
//  Happs
//
//  Created by Rafa Abes on 10/31/26.
//


// CODE OVERVIEW
// A caseless enum used only as a namespace for static functions. Views such as the list rows,
// map pins and recap photos call these functions to get the exact string they pass to
// .accessibilityLabel. Keeping the wording here (and not inline in each view) means it is
// consistent across screens and can be unit tested: each function depends only on its
// arguments, so no Firebase, view or simulator state is needed. Callers pass plain Strings
// and Ints rather than model objects, which keeps this file free of dependencies on Happ or
// UserProfile.
import Foundation

/// Namespace (a caseless enum cannot be instantiated) for pure functions that build VoiceOver sentences.
enum AccessibilityText {
    /// "Unread. Title. Body. 2 hours ago". Unread is said first so it is never missed.
    /// - Parameters:
    ///   - isRead: When false, "Unread" is prepended because the unread dot alone is invisible to VoiceOver.
    ///   - date: Optional timestamp, spoken as relative wording such as "2 hours ago".
    ///   - now: Defaulted for convenience; the current body does not read it (the relative
    ///     formatter measures against the system clock).
    static func notificationRow(isRead: Bool, title: String, body: String, date: Date?, now: Date = Date()) -> String {
        var parts: [String] = []
        if !isRead { parts.append("Unread") }
        parts.append(title)
        if !body.isEmpty { parts.append(body) }
        // `.named` presentation gives words such as "yesterday"; `.wide` spells out units ("2 hours ago") so VoiceOver reads them clearly.
        if let date {
            parts.append(date.formatted(.relative(presentation: .named, unitsStyle: .wide)))
        }
        // Full stops make VoiceOver pause between the parts.
        return parts.joined(separator: ". ")
    }

    /// "Sam, on campus, Busy" or "Sam, hidden".
    static func friendRow(name: String, status: String, isVisible: Bool, isOnCampus: Bool) -> String {
        guard isVisible else { return "\(name), hidden" }
        var parts = [name]
        if isOnCampus { parts.append("on campus") }
        parts.append(status)
        return parts.joined(separator: ", ")
    }

    /// "Groups, 3 groups" or "Groups, 2 new invitations".
    static func groupsRow(groupCount: Int, newInvitations: Int) -> String {
        // Pending invitations take priority over the plain group count because they need action.
        if newInvitations > 0 {
            return "Groups, \(newInvitations) new \(newInvitations == 1 ? "invitation" : "invitations")"
        }
        return "Groups, \(groupCount) \(groupCount == 1 ? "group" : "groups")"
    }

    /// "Badminton, Sport, Joined, Sports Hall, 5:56 PM to 7:00 PM".
    static func happRow(title: String, badge: String?, category: String, location: String, time: String) -> String {
        // Order matters: the title comes first, then the optional badge (for example Joined), category, place, time.
        var parts = [title]
        if let badge { parts.append(badge) }
        parts.append(category)
        if !location.isEmpty { parts.append(location) }
        parts.append(time)
        return parts.joined(separator: ", ")
    }

    /// Map pin for a Happ: "Badminton, Sport, 3 going".
    static func happPin(title: String, category: String, goingCount: Int) -> String {
        "\(title), \(category), \(goingCount) going"
    }

    /// Map pin for a friend: "Sam, Busy, on the map".
    static func friendPin(name: String, status: String) -> String {
        "\(name), \(status), on the map"
    }

    /// "Photo by Rafa. Great game" or "Photo by Rafa".
    static func recapPhoto(author: String, caption: String) -> String {
        caption.isEmpty ? "Photo by \(author)" : "Photo by \(author). \(caption)"
    }

    /// Position text for several photos picked at once: "Photo 2 of 3".
    static func photoPosition(index: Int, total: Int) -> String {
        "Photo \(index) of \(total)"
    }
}
