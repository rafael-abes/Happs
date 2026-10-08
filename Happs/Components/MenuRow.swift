//
//  MenuRow.swift
//  Happs
//
//  Created by Rafa Abes on 10/1/26.
//
import SwiftUI

struct MenuRow: View {
    let systemImage: String
    let title: String
    var action: () -> Void = {}
    
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 28
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.medium))
                    .frame(width: iconSize, height: iconSize)
                    .background(.quaternary, in: Circle())
                
                Text(title)
                    .font(.body)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
