//
//  AvatarView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//
import SwiftUI

enum AvatarSymbols {
    static let fallback = "person.fill"
    static let all = [
        "person.fill", "face.smiling.fill", "pawprint.fill", "leaf.fill",
        "flame.fill", "bolt.fill", "star.fill", "heart.fill",
        "moon.fill", "hare.fill", "sportscourt.fill", "music.note"
    ]

    /// What VoiceOver says for each profile picture.
    static let names: [String: String] = [
        "person.fill": "Person",
        "face.smiling.fill": "Smiling face",
        "pawprint.fill": "Paw print",
        "leaf.fill": "Leaf",
        "flame.fill": "Flame",
        "bolt.fill": "Lightning bolt",
        "star.fill": "Star",
        "heart.fill": "Heart",
        "moon.fill": "Moon",
        "hare.fill": "Hare",
        "sportscourt.fill": "Sports court",
        "music.note": "Music note"
    ]

    static func name(for symbol: String?) -> String {
        names[symbol ?? fallback] ?? "Profile picture"
    }
}

struct AvatarView: View {
    let symbol: String?
    /// Custom profile picture (JPEG). Falls back to the symbol when nil or undecodable.
    var photo: Data? = nil
    var size: CGFloat = 44
    var ringColor: Color? = nil
    /// Optional SF Symbol drawn in the corner so status is not shown by colour alone.
    var badgeSymbol: String? = nil

    var body: some View {
        face
            .overlay(Circle().stroke(ringColor ?? Color.clear, lineWidth: 3))
            .overlay(alignment: .bottomTrailing) { badge }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var face: some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: symbol ?? AvatarSymbols.fallback)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.happsGreenFill, in: Circle())
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let badgeSymbol {
            Image(systemName: badgeSymbol)
                .font(.system(size: size * 0.24, weight: .bold))
                .foregroundStyle(.primary)
                .padding(size * 0.09)
                .background(Color(.systemBackground), in: Circle())
                .overlay(Circle().stroke(ringColor ?? Color.clear, lineWidth: 1.5))
                .offset(x: size * 0.06, y: size * 0.06)
        }
    }
}
