//
//  CampusLockedView.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//
// CODE OVERVIEW
// The "map is locked" screen shown on the Friends map and the Happs list when the user is not
// confirmed to be on campus. CampusAccess is a small state enum (locating, no permission,
// outside, inside) derived from LocationService, and CampusLockedView renders a card on top of
// a blurred, non-interactive map for those states. The parent screens decide when to show it
// and pass in the Happs and online friends to summarise, so this view only displays data.
// It owns one piece of state, `now`, kept fresh by the expiryClock modifier (ClockTicker.swift)
// so the "active now" count changes exactly when a Happ starts or ends.
import SwiftUI
import MapKit

/// Where the user stands relative to the campus geofence. Drives which message the locked card shows.
enum CampusAccess {
    case locating, noPermission, outside, inside
}

/// Maps the service's raw authorization and location values onto one CampusAccess state.
extension LocationService {
    var campusAccess: CampusAccess {
        // Permission is checked first: with access denied or restricted, no location will ever arrive.
        switch authorizationStatus {
        case .denied, .restricted:
            return .noPermission
        default:
            break
        }
        // Permission is fine but no fix yet, so we are still locating.
        guard currentCoordinate != nil else { return .locating }
        return isInsideCampus ? .inside : .outside
    }
}

/// Locked-state card over a blurred map, with a live count of active Happs and a line about friends on campus.
struct CampusLockedView: View {
    /// Current access state; chooses the icon, headline and detail text.
    let access: CampusAccess
    /// All Happs, used only to count the ones active right now.
    let happs: [Happ]
    /// Friends currently on campus; shown as a small avatar stack and a count.
    let onlineFriends: [UserProfile]
    
    // @State because this view owns the clock value. expiryClock updates it at Happ start/end times.
    @State private var now = Date()
    
    /// How many Happs are active at the current `now` (see Happ+Active.swift for the rule).
    private var activeCount: Int {
        happs.filter { $0.isActive(at: now) }.count
    }
    
    /// Main title: a locating message, or the number of active Happs with correct singular/plural wording.
    private var headline: String {
        if access == .locating { return "Finding your location" }
        switch activeCount {
        case 0: return "No happs active right now"
        case 1: return "1 happ active now"
        default: return "\(activeCount) happs active now"
        }
    }
    
    /// Explanation line that depends on why the map is locked.
    private var detail: String {
        switch access {
        case .locating: "Hang tight while we check whether you're on campus."
        case .noPermission: "Turn on location for Happs in Settings to see what's happening on campus."
        case .outside, .inside: "Head to campus to see where everyone is and join in."
        }
    }

    /// Singular/plural sentence for the friends-on-campus count.
    private var friendsLine: String {
        onlineFriends.count == 1
            ? "1 friend is on campus now"
            : "\(onlineFriends.count) friends are on campus now"
    }
    
    // Blurred map at the back, card in a ScrollView on top. basedOnSize stops bouncing when everything fits.
    var body: some View {
        ZStack {
            blurredCampus
            ScrollView {
                card
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // Re-evaluates `now` when the next Happ boundary passes, so the count updates without polling.
        .expiryClock($now, boundaries: happs.clockBoundaries)
    }
    
    /// Decorative backdrop: a real MapKit map with the campus polygon, then blurred and disabled
    /// (interactionModes empty, hit testing off) so it looks like a map but cannot be used.
    private var blurredCampus: some View {
        Map(initialPosition: .region(LocationService.campusRegion), interactionModes: []) {
            MapPolygon(coordinates: LocationService.campusBoundary)
                .foregroundStyle(.green.opacity(0.25))
                .stroke(.green, lineWidth: 2)
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .blur(radius: 9)
        .allowsHitTesting(false)
        .clipped()
        .accessibilityHidden(true)
    }
    
    /// The visible card: icon (spinner while locating, lock otherwise), headline, detail and friends.
    private var card: some View {
        VStack(spacing: 12) {
            if access == .locating {
                ProgressView()
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.happsGreenText)
                    .accessibilityHidden(true)
            }
            Text(headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            friendsOnline
        }
        .padding(24)
        // A system material keeps the text readable over the busy blurred map in light and dark mode.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(32)
        .accessibilityElement(children: .combine)
    }
    
    /// Avatars of up to five online friends (overlapping via negative spacing) and the friends line.
    /// Hidden entirely while locating or when nobody is online.
    @ViewBuilder
    private var friendsOnline: some View {
        if access != .locating && !onlineFriends.isEmpty {
            VStack(spacing: 6) {
                HStack(spacing: -8) {
                    // prefix(5) limits the stack so it never grows wide; negative HStack spacing overlaps the avatars.
                    ForEach(onlineFriends.prefix(5)) { friend in
                        AvatarView(symbol: friend.avatarSymbol, photo: friend.avatarPhoto, size: 30, ringColor: Color(.systemBackground))
                    }
                }
                .accessibilityHidden(true)
                Text(friendsLine)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 4)
        }
    }
}
