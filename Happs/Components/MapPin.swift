//
//  MapPin.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//
import SwiftUI

struct HappPin: View {
    let happ: Happ
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: happ.category.symbolName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(happ.category.tint, in: Circle())
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(happ.title)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(happ.participantIDs.count) going")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: Capsule())
            .overlay(Capsule().stroke(happ.category.tint, lineWidth: isSelected ? 3 : 2))
            .shadow(radius: 4, y: 2)
            
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(happ.category.tint)
                .offset(y: -2)
        }
        .scaleEffect(isSelected ? 1.15 : 1, anchor: .bottom)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

struct FriendPin: View {
    let friend: UserProfile
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            AvatarView(symbol: friend.avatarSymbol, size: 38, ringColor: friend.status.color)
                .shadow(radius: 3, y: 1)
                .scaleEffect(isSelected ? 1.2 : 1)
            Text(friend.displayName)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

