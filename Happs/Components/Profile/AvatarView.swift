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
}

struct AvatarView: View {
    let symbol: String?
    var size: CGFloat = 44
    var ringColor: Color? = nil
    
    var body: some View {
        Image(systemName: symbol ?? AvatarSymbols.fallback)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.happsGreen, in: Circle())
            .overlay(Circle().stroke(ringColor ?? Color.clear, lineWidth: 3))
    }
}
