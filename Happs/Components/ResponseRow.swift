//
//  ResponseRow.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//
// CODE OVERVIEW
// ResponseRow is a reusable row for anything the user must accept or decline (friend requests,
// group or Happ invitations). It is a dumb presentational view: it owns no data and never talks
// to Firestore. The parent passes the text and two closures (onAccept, onDecline), so the parent
// or its store decides what accepting means. This keeps the row reusable and easy to preview.
// Layout uses ViewThatFits to choose between a side by side and a stacked arrangement.
import SwiftUI

/// Row with a title, optional subtitle and Accept / Decline buttons.
struct ResponseRow: View {
    /// Main line, usually the person or group name. Also used in the VoiceOver labels.
    let title: String
    /// Optional smaller second line (for example what the request is for).
    let subtitle: String?
    /// Callbacks supplied by the parent. The row only reports the tap, it does not act on it.
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        // ViewThatFits tries each child in order and shows the first that fits the width.
        // First choice: one line. Fallback: labels above buttons (large Dynamic Type or long names).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                labels.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                buttons.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 10) {
                labels
                buttons
            }
        }
    }

    /// Title and subtitle stacked, read by VoiceOver as one element.
    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The Accept and Decline pair. Defined once and reused in both layouts above.
    private var buttons: some View {
        HStack(spacing: 8) {
            Button { onAccept() } label: {
                Text("Accept").lineLimit(1).frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.happsGreenFill)
            .accessibilityLabel("Accept \(title)")
            .accessibilityHint("Accepts this request or invitation.")

            Button { onDecline() } label: {
                Text("Decline").lineLimit(1).frame(minHeight: 44).foregroundStyle(.primary)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Decline \(title)")
            .accessibilityHint("Declines this request or invitation.")
        }
        // Applied to the whole HStack: small control style, while each label sets its own 44 pt height.
        .controlSize(.small)
    }
}
