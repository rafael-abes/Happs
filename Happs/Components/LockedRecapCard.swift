//
//  LockedRecapCard.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//
import SwiftUI
 
/// What people who did not attend see: blurred colour blocks from the tiny previews,
/// a lock, and a photo count. The real photos are never downloaded for them.
struct LockedRecapCard: View {
    let happ: Happ
    let previews: [RecapPreview]
 
    private var countText: String {
        let people = Set(previews.map(\.authorID)).count
        if previews.isEmpty { return "No photos shared yet." }
        let photos = previews.count == 1 ? "1 photo" : "\(previews.count) photos"
        let who = people == 1 ? "1 person" : "\(people) people"
        return "\(photos) from \(who). Join the next Happ so you don't miss out."
    }
 
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                tiles
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
 
            Text(happ.title)
                .font(.headline)
            Text(countText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked recap for \(happ.title). \(countText)")
    }
 
    @ViewBuilder
    private var tiles: some View {
        if previews.isEmpty {
            Rectangle().fill(Color(.tertiarySystemFill))
        } else {
            HStack(spacing: 4) {
                ForEach(previews.prefix(3)) { preview in
                    tile(preview)
                }
            }
        }
    }
 
    /// The photo sits in an overlay, so its own shape never changes the tile's size.
    /// Every tile gets an equal share of the width, and the lock stays centred.
    private func tile(_ preview: RecapPreview) -> some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill))
            .overlay {
                if let data = preview.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .blur(radius: 14)
                        .overlay(Color.black.opacity(0.15))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}
