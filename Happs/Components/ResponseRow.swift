//
//  ResponseRow.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//
import SwiftUI

struct ResponseRow: View {
    let title: String
    let subtitle: String?
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
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
    
    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var buttons: some View {
        HStack(spacing: 8) {
            Button { onAccept() } label: { Text("Accept").lineLimit(1) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            Button { onDecline() } label: { Text("Decline").lineLimit(1) }
                .buttonStyle(.bordered)
        }
        .controlSize(.small)
    }
}
