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
    @State private var errorMessage: String?
    
    private var notificationsTitle: String {
        let unread = notificationStore.unreadCount
        return unread > 0 ? "Notifications (\(unread))" : "Notifications"
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
            
            Menu {
                ForEach(UserStatus.allCases) { status in
                    Button(status.rawValue) { updateStatus(status) }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(profileStore.profile?.status.color ?? UserStatus.available.color)
                        .frame(width: 8, height: 8)
                    Text(profileStore.profile?.status.rawValue ?? "Available")
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
    
    private var invisibleModeCard: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { profileStore.profile?.isVisible == false },
                set: { setInvisible($0) }
            ))
            .labelsHidden()
            Text("Invisible Mode")
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
            Text("Dark Mode")
            Spacer()
            Toggle("", isOn: $prefersDarkMode).labelsHidden()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    
    private var menuRows: some View {
        VStack(spacing: 10) {
            MenuRow(systemImage: "house.fill", title: "My Profile") { isPresentingEditor = true }
            MenuRow(systemImage: "bell.fill", title: notificationsTitle) { isPresentingNotifications = true }
            MenuRow(systemImage: "calendar", title: "Schedule")
            MenuRow(systemImage: "square.and.pencil", title: "Preferences")
            MenuRow(systemImage: "line.3.horizontal", title: "Settings")
        }
    }
    
    private var signOutButton: some View {
        Button(role: .destructive, action: signOut) {
            Text("Sign Out").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.top, 10)
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
