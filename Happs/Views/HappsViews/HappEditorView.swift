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
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var details: String
    @State private var location: String
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var category: HappCategory
    @State private var startTime: Date
    @State private var invitedGroupIDs: Set<String> = []
    @State private var isSaving = false
    @State private var isPresentingLocationPicker = false
    @State private var errorMessage: String?
    
    init(happ: Happ? = nil) {
        editing = happ
        _title = State(initialValue: happ?.title ?? "")
        _details = State(initialValue: happ?.details ?? "")
        _location = State(initialValue: happ?.location ?? "")
        _selectedCoordinate = State(initialValue: happ?.coordinate)
        _category = State(initialValue: happ?.category ?? .happs)
        _startTime = State(initialValue: happ?.startTime ?? Date())
    }
    
    var body: some View {
        Form {
            Section("Happ Title") {
                TextField("What's happening?", text: $title)
            }
            
            Section("Location") {
                Button {
                    isPresentingLocationPicker = true
                } label: {
                    HStack {
                        Text(location.isEmpty ? "Add Location" : location)
                            .foregroundStyle(location.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "mappin.and.ellipse")
                    }
                }
                .buttonStyle(.plain)
            }
            
            Section("When") {
                DatePicker("Time", selection: $startTime)
            }
            
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
                TextField("Add notes or anything else", text: $details, axis: .vertical)
                    .lineLimit(3...6)
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
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $isPresentingLocationPicker) {
            LocationPickerView(category: category, selectedName: $location, selectedCoordinate: $selectedCoordinate)
        }
        .alert("Couldn't Save Happ", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
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
    
    private func save() {
        guard let user = authService.user else {
            errorMessage = "Sign in again before saving."
            return
        }
        
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
                        latitude: selectedCoordinate?.latitude,
                        longitude: selectedCoordinate?.longitude
                    )
                } else {
                    try await happStore.createHapp(
                        title: title,
                        details: details,
                        location: location,
                        category: category,
                        startTime: startTime,
                        creatorID: user.uid,
                        creatorName: user.displayName ?? user.email ?? "Someone",
                        latitude: selectedCoordinate?.latitude,
                        longitude: selectedCoordinate?.longitude,
                        invitedIDs: invitedFriendIDs
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
