//
//  LockedRecapCard.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//
// CODE OVERVIEW
// The "teaser" a user sees for a Happ recap they did not attend.
// SwiftUI view: the parent screens (HappsListView and RecapTimelineView) pass in the
// RecapPreview values, so this view holds no state and does no networking. Only the tiny
// preview data is drawn, heavily blurred, so non-attendees can see that photos exist but not
// what they show (the privacy and "fear of missing out" design). The whole card is collapsed
// into one accessibility element with a single combined label.
import SwiftUI
 
/// What people who did not attend see: blurred colour blocks from the tiny previews,
/// a lock, and a photo count. The real photos are never downloaded for them.
struct LockedRecapCard: View {
    /// The Happ whose recap is locked. Only its title is shown.
    let happ: Happ
    /// Tiny preview images plus author IDs for the recap photos. Used for the blurred tiles and the counts.
    let previews: [RecapPreview]
 
    /// Sentence under the title, also reused in the VoiceOver label.
    private var countText: String {
        // A Set of author IDs, so someone who posted several photos is counted once.
        let people = Set(previews.map(\.authorID)).count
        if previews.isEmpty { return "No photos shared yet." }
        let photos = previews.count == 1 ? "1 photo" : "\(previews.count) photos"
        let who = people == 1 ? "1 person" : "\(people) people"
        return "\(photos) from \(who). Join the next Happ so you don't miss out."
    }
 
    // The ZStack layers the lock on top of the blurred tiles; the title and count sit below in a VStack.
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
            // Clip so the blurred tiles (which are scaled to fill) cannot spill outside the rounded band.
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
 
            Text(happ.title)
                .font(.headline)
            Text(countText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        // .ignore drops the children and replaces them with the single label below, so VoiceOver reads one stop.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked recap for \(happ.title). \(countText)")
    }
 
    /// Up to three blurred preview tiles side by side, or a single empty grey block when there are no previews.
    /// @ViewBuilder lets the if/else return different view types.
    @ViewBuilder
    private var tiles: some View {
        if previews.isEmpty {
            Rectangle().fill(Color(.tertiarySystemFill))
        } else {
            HStack(spacing: 4) {
                // prefix(3) caps the strip at three tiles; RecapPreview must be Identifiable for ForEach to accept it.
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
                        // Blur is applied on the device, on top of an already tiny image, so the content cannot be recovered.
                        .blur(radius: 14)
                        .overlay(Color.black.opacity(0.15))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}
