//
//  ProfileView.swift
//  Happs
//
//  Created by Rafa Abes on 10/1/26.
//
import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var notificationStore: NotificationStore
    @EnvironmentObject private var locationService: LocationService
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 28
    @State private var isPresentingEditor = false
    @State private var isPresentingNotifications = false
    @State private var isShowingAbout = false
    @State private var errorMessage: String?

    private var notificationsTitle: String {
        let unread = notificationStore.unreadCount
        return unread > 0 ? "Notifications (\(unread))" : "Notifications"
    }

    private var currentStatusName: String {
        profileStore.profile?.status.rawValue ?? "Available"
    }

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
            .navigationDestination(isPresented: $isShowingAbout) { AboutView() }
            .sheet(isPresented: $isPresentingEditor) { ProfileEditorView() }
            .sheet(isPresented: $isPresentingNotifications) { NotificationsView() }
            .alert("Something Went Wrong", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            AvatarView(symbol: profileStore.profile?.avatarSymbol, size: avatarSize)
            Text(authService.user?.displayName ?? "Happs User")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Menu {
                ForEach(UserStatus.allCases) { status in
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

    private var invisibleModeCard: some View {
        HStack {
            Toggle("Invisible Mode", isOn: Binding(
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

    private var menuRows: some View {
        VStack(spacing: 10) {
            MenuRow(systemImage: "house.fill", title: "My Profile", hint: "Opens your profile editor.") { isPresentingEditor = true }
            MenuRow(systemImage: "bell.fill", title: notificationsTitle, hint: "Opens your notifications.") { isPresentingNotifications = true }
            MenuRow(systemImage: "calendar", title: "Schedule", hint: "Not available yet.")
            MenuRow(systemImage: "square.and.pencil", title: "Preferences", hint: "Not available yet.")
            MenuRow(systemImage: "line.3.horizontal", title: "Settings", hint: "Not available yet.")
            MenuRow(systemImage: "info.circle", title: "About", hint: "About Happs, the developer and credits.") { isShowingAbout = true }
        }
    }

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

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func updateStatus(_ status: UserStatus) {
        guard let userID = authService.user?.uid else { return }
        Task {
            do { try await profileStore.updateStatus(status, for: userID) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func setInvisible(_ invisible: Bool) {
        guard let userID = authService.user?.uid else { return }
        Task {
            do { try await profileStore.setVisible(!invisible, for: userID) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func signOut() {
        guard let userID = authService.user?.uid else { return }
        Task {
            await locationService.clearLiveLocation(for: userID)
            do { try authService.signOut() } catch { errorMessage = error.localizedDescription }
        }
    }
}
