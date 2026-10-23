//
//  HappEditorView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//
import SwiftUI
import CoreLocation
import FirebaseAuth
 
struct HappEditorView: View {
    private let editing: Happ?
 
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var happStore: HappStore
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var aiService: AIService
    @Environment(\.dismiss) private var dismiss
 
    @State private var title: String
    @State private var details: String
    @State private var location: String
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var isOffCampus: Bool
    @State private var category: HappCategory
    @State private var startTime: Date
    @State private var hasEndTime: Bool
    @State private var endTime: Date
    @State private var invitedGroupIDs: Set<String> = []
    @State private var isSaving = false
    @State private var isPresentingLocationPicker = false
    @State private var errorMessage: String?
    @State private var showAssistant = false
 
    init(happ: Happ? = nil) {
        editing = happ
        let seed = happ.map { HappDraft(happ: $0) } ?? HappDraft.blank
        _title = State(initialValue: seed.title)
        _details = State(initialValue: seed.details)
        _location = State(initialValue: seed.location)
        _selectedCoordinate = State(initialValue: seed.coordinate)
        _isOffCampus = State(initialValue: seed.isOffCampus)
        _category = State(initialValue: seed.category)
        _startTime = State(initialValue: seed.startTime)
        _hasEndTime = State(initialValue: seed.endTime != nil)
        _endTime = State(initialValue: seed.endTime ?? seed.startTime.addingTimeInterval(60 * 60))
    }
 
    var body: some View {
        Form {
            if aiService.isEnabled {
                Section {
                    Button { showAssistant = true } label: {
                        Label("Describe it", systemImage: "sparkles")
                    }
                }
            }
            if editing == nil {
                eventSection
            }
 
            Section("Happ Title") {
                HStack {
                    TextField("What's happening?", text: $title)
                    MicButton(text: $title, id: "editor-title")
                }
            }
 
            Section("Location") {
                Button {
                    isPresentingLocationPicker = true
                } label: {
                    HStack {
                        Text(location.isEmpty ? "Add Location" : location)
                            .foregroundStyle(location.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: isOffCampus ? "location.slash" : "mappin.and.ellipse")
                    }
                }
                .buttonStyle(.plain)
            }
 
            whenSection
 
            Section("Category") {
                Picker("Category", selection: $category) {
                    ForEach(HappCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
            }
 
            if editing == nil {
                inviteSection
            }
 
            Section("Details") {
                HStack(alignment: .top) {
                    TextField("Add notes or anything else", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                    MicButton(text: $details, id: "editor-details")
                }
            }
        }
        .navigationTitle(editing == nil ? "New Happ" : "Edit Happ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Add Happ" : "Save") { save() }.disabled(isSaving)
            }
        }
        .onChange(of: startTime) { _, newStart in
            if endTime <= newStart {
                endTime = newStart.addingTimeInterval(60 * 60)
            }
        }
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $isPresentingLocationPicker) {
            LocationPickerView(
                category: category,
                selectedName: $location,
                selectedCoordinate: $selectedCoordinate,
                isOffCampus: $isOffCampus
            )
        }
        .sheet(isPresented: $showAssistant) {
            AssistantSheet { draft, groupID in
                apply(draft)
                if let groupID, editing == nil {
                    invitedGroupIDs.insert(groupID)
                }
            }
        }
        .alert("Couldn't Save Happ", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }
 
    private var eventSection: some View {
        Section {
            NavigationLink {
                EventSuggestionsView(onSelect: apply)
            } label: {
                Label("Start from a Ticketmaster event", systemImage: "ticket.fill")
            }
        } footer: {
            Text("Browse upcoming events near campus and turn one into a Happ.")
        }
    }
 
    private var whenSection: some View {
        Section {
            DatePicker("Starts", selection: $startTime)
            Toggle("Set an end time", isOn: $hasEndTime)
            if hasEndTime {
                DatePicker("Ends", selection: $endTime, in: startTime...)
            }
        } header: {
            Text("When")
        } footer: {
            if !hasEndTime {
                Text("With no end time, a Happ stays up for 3 hours after it starts.")
            }
        }
    }
 
    private var inviteSection: some View {
        Section {
            if groupStore.groups.isEmpty {
                Text("Make a group in the Friends tab to invite people in one tap.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupStore.groups) { group in
                    Toggle(isOn: inviteBinding(for: group)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                            Text("\(group.memberIDs.count) members")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Invite a group")
        }
    }
 
    private func inviteBinding(for group: FriendGroup) -> Binding<Bool> {
        Binding(
            get: { invitedGroupIDs.contains(group.id) },
            set: { isOn in
                if isOn {
                    invitedGroupIDs.insert(group.id)
                } else {
                    invitedGroupIDs.remove(group.id)
                }
            }
        )
    }
 
    private var invitedFriendIDs: [String] {
        let members = groupStore.groups
            .filter { invitedGroupIDs.contains($0.id) }
            .flatMap(\.memberIDs)
            .filter { $0 != authService.user?.uid }
        return Array(Set(members))
    }
 
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
 
    private func apply(_ seed: HappDraft) {
        title = seed.title
        details = seed.details
        location = seed.location
        selectedCoordinate = seed.coordinate
        isOffCampus = seed.isOffCampus
        category = seed.category
        startTime = seed.startTime
        hasEndTime = seed.endTime != nil
        endTime = seed.endTime ?? seed.startTime.addingTimeInterval(60 * 60)
    }
 
    private func save() {
        guard let user = authService.user else {
            errorMessage = "Sign in again before saving."
            return
        }
 
        let finalEnd: Date? = hasEndTime ? endTime : nil
 
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if let editing {
                    try await happStore.updateHapp(
                        editing,
                        title: title,
                        details: details,
                        location: location,
                        category: category,
                        startTime: startTime,
                        endTime: finalEnd,
                        latitude: selectedCoordinate?.latitude,
                        longitude: selectedCoordinate?.longitude,
                        isOffCampus: isOffCampus
                    )
                } else {
                    try await happStore.createHapp(
                        title: title,
                        details: details,
                        location: location,
                        category: category,
                        startTime: startTime,
                        endTime: finalEnd,
                        creatorID: user.uid,
                        creatorName: user.displayName ?? user.email ?? "Someone",
                        latitude: selectedCoordinate?.latitude,
                        longitude: selectedCoordinate?.longitude,
                        isOffCampus: isOffCampus,
                        invitedIDs: invitedFriendIDs,
                        audienceIDs: friendStore.onCampusFriendIDs
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
