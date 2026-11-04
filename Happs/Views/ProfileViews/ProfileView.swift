//
//  ProfileView.swift
//  Happs
//
//  Created by Rafa Abes on 10/1/26.
//
// CODE OVERVIEW
// The "Me" tab. It shows the user's avatar, name and status, the Invisible Mode and Dark Mode
// switches, a menu of rows that open the editor, notifications, privacy and about screens, and Sign
// Out. It owns no data: the profile comes from ProfileStore, the name from AuthService and the unread
// count from NotificationStore, all injected as environment objects, and writes go through those
// stores. Dark Mode is a view preference kept in @AppStorage (UserDefaults), not in Firestore, so
// it applies instantly on this device. Sign out first clears live location so friends stop seeing
// the user.
//
import SwiftUI
import FirebaseAuth

/// Root view of the Me tab.
struct ProfileView: View {
    // Shared stores and services injected by the app root.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var notificationStore: NotificationStore
    @EnvironmentObject private var locationService: LocationService
    // @AppStorage reads and writes UserDefaults and re-renders the view when it changes. (The code that applies the preference to the whole app lives elsewhere.)
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    // Sizes that scale with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 28
    // Presentation flags: sheets for the editor and notifications, pushed screens for About and Privacy.
    @State private var isPresentingEditor = false
    @State private var isPresentingNotifications = false
    @State private var isShowingAbout = false
    @State private var isShowingPrivacy = false
    @State private var errorMessage: String?

    /// Menu title with the unread count appended when there are unread notifications.
    private var notificationsTitle: String {
        let unread = notificationStore.unreadCount
        return unread > 0 ? "Notifications (\(unread))" : "Notifications"
    }

    /// Display name of the user's status; "Available" until the profile has loaded.
    private var currentStatusName: String {
        profileStore.profile?.status.rawValue ?? "Available"
    }

    // The body is assembled from small computed-property subviews to keep it readable.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    invisibleModeCard
                    appearanceCard
                    menuRows
                    signOutButton
                }
                .padding(20)
            }
            .navigationTitle("Me")
            // Boolean-driven navigation: the menu row sets the flag and the stack pushes the screen.
            .navigationDestination(isPresented: $isShowingAbout) { AboutView() }
            .navigationDestination(isPresented: $isShowingPrivacy) { PrivacySafetyView() }
            .sheet(isPresented: $isPresentingEditor) { ProfileEditorView() }
            .sheet(isPresented: $isPresentingNotifications) { NotificationsView() }
            .alert("Something Went Wrong", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    /// Avatar, name and a Menu to change status.
    private var header: some View {
        VStack(spacing: 6) {
            AvatarView(symbol: profileStore.profile?.avatarSymbol, photo: profileStore.profile?.avatarPhoto, size: avatarSize)
            Text(authService.user?.displayName ?? "Happs User")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Menu {
                ForEach(UserStatus.allCases) { status in
                    // One menu item per UserStatus case (the enum is CaseIterable).
                    Button(status.rawValue) { updateStatus(status) }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(profileStore.profile?.status.color ?? UserStatus.available.color)
                        .frame(width: 8, height: 8)
                    Text(currentStatusName)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Status")
            .accessibilityValue(currentStatusName)
            .accessibilityHint("Double tap to choose Available, In Class, Busy or Do Not Disturb.")
        }
    }

    /// Invisible Mode switch. On means isVisible is false in the profile (friends cannot see the user on the map).
    private var invisibleModeCard: some View {
        HStack {
            Toggle("Invisible Mode", isOn: Binding(
                // The switch shows "invisible", which is the opposite of the stored isVisible flag, so the value is inverted here and in setInvisible.
                get: { profileStore.profile?.isVisible == false },
                set: { setInvisible($0) }
            ))
            .labelsHidden()
            .accessibilityHint("When on, friends cannot see you on the map.")
            Text("Invisible Mode")
                .accessibilityHidden(true)
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Dark Mode switch bound directly to the @AppStorage preference.
    private var appearanceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: prefersDarkMode ? "moon.fill" : "sun.max.fill")
                .font(.callout.weight(.medium))
                .frame(width: iconSize, height: iconSize)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)
            Text("Dark Mode")
                .accessibilityHidden(true)
            Spacer()
            Toggle("Dark Mode", isOn: $prefersDarkMode)
                .labelsHidden()
                .accessibilityHint("Switches the app between light and dark appearance.")
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Navigation-style rows. Rows without an action are placeholders for features that are not built yet.
    private var menuRows: some View {
        VStack(spacing: 10) {
            MenuRow(systemImage: "house.fill", title: "My Profile", hint: "Opens your profile editor.") { isPresentingEditor = true }
            MenuRow(systemImage: "bell.fill", title: notificationsTitle, hint: "Opens your notifications.") { isPresentingNotifications = true }
            MenuRow(systemImage: "calendar", title: "Schedule", hint: "Not available yet.")
            MenuRow(systemImage: "square.and.pencil", title: "Preferences", hint: "Not available yet.")
            MenuRow(systemImage: "line.3.horizontal", title: "Settings", hint: "Not available yet.")
            MenuRow(systemImage: "hand.raised.fill", title: "Privacy and Safety", hint: "Blocked people, Gemini permission, policies and account deletion.") { isShowingPrivacy = true }
            MenuRow(systemImage: "info.circle", title: "About", hint: "About Happs, the developer and credits.") { isShowingAbout = true }
        }
    }

    /// Destructive Sign Out button.
    private var signOutButton: some View {
        Button(role: .destructive, action: signOut) {
            Text("Sign Out")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.top, 10)
        .accessibilityHint("Signs you out and hides your location from friends.")
    }

    /// Bridges the optional error string to the alert's Bool (setting false clears the message).
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// Writes the new status via ProfileStore; shows an alert if it fails.
    /// - Parameter status: the status chosen in the menu.
    private func updateStatus(_ status: UserStatus) {
        guard let userID = authService.user?.uid else { return }
        Task {
            do { try await profileStore.updateStatus(status, for: userID) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    /// Writes the visibility flag (inverted from the switch) via ProfileStore.
    /// - Parameter invisible: the new switch value.
    private func setInvisible(_ invisible: Bool) {
        guard let userID = authService.user?.uid else { return }
        Task {
            do { try await profileStore.setVisible(!invisible, for: userID) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    /// Clears the live location document first, then signs out of Firebase Auth.
    /// Order matters: after sign out the user id is gone, and clearing needs it.
    private func signOut() {
        guard let userID = authService.user?.uid else { return }
        Task {
            // This service call does not throw; it ignores a failed cleanup write so sign out still proceeds.
            await locationService.clearLiveLocation(for: userID)
            do { try authService.signOut() } catch { errorMessage = error.localizedDescription }
        }
    }
}

