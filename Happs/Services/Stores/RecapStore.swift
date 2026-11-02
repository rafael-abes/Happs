//
//  RecapStore.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//
import Foundation
import FirebaseFirestore
import Combine

/// One photo the user has picked but not posted yet.
struct RecapDraft: Identifiable {
    let id = UUID()
    let full: Data
    let preview: Data
    var caption = ""
}

/// Owns the recap listeners and writes. Views never touch Firestore or Supabase directly.
@MainActor
final class RecapStore: ObservableObject {
    @Published private(set) var previewsByHapp: [String: [RecapPreview]] = [:]
    @Published private(set) var recapsByHapp: [String: [Recap]] = [:]
    @Published var errorMessage: String?
    /// Set from ContentView (SafetyStore).
    @Published var blockedIDs: Set<String> = []
    @Published var hiddenIDs: Set<String> = []

    private var db: Firestore { Firestore.firestore() }
    private let storage = SupabaseStorageService.shared
    private var previewListeners: [String: ListenerRegistration] = [:]
    private var recapListeners: [String: ListenerRegistration] = [:]

    // MARK: Previews (any signed-in user)

    /// Keeps exactly these Happs' previews live. Used by the Happs feed.
    func observePreviews(for happIDs: [String]) {
        let wanted = Set(happIDs)
        for id in Array(previewListeners.keys) where !wanted.contains(id) {
            previewListeners[id]?.remove()
            previewListeners[id] = nil
            previewsByHapp[id] = nil
        }
        for id in wanted { ensurePreviews(happID: id) }
    }

    /// Adds one Happ's preview listener without touching the others.
    func ensurePreviews(happID: String) {
        guard previewListeners[happID] == nil else { return }
        previewListeners[happID] = db.collection("happs").document(happID)
            .collection("recapPreviews")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.log(error); return }
                let items = snapshot?.documents.compactMap {
                    RecapPreview(id: $0.documentID, happID: happID, data: $0.data())
                } ?? []
                self.previewsByHapp[happID] = items.sorted { $0.createdAt < $1.createdAt }
            }
    }

    // MARK: Recaps (attendees only)

    func observeRecaps(happID: String) {
        guard recapListeners[happID] == nil else { return }
        recapListeners[happID] = db.collection("happs").document(happID)
            .collection("recaps")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.log(error); return }
                let items = snapshot?.documents.compactMap {
                    Recap(id: $0.documentID, happID: happID, data: $0.data())
                } ?? []
                self.recapsByHapp[happID] = items.sorted { $0.createdAt > $1.createdAt }
            }
    }

    func stopRecaps(happID: String) {
        recapListeners[happID]?.remove()
        recapListeners[happID] = nil
    }

    /// Call on sign-out.
    func stopAll() {
        previewListeners.values.forEach { $0.remove() }
        recapListeners.values.forEach { $0.remove() }
        previewListeners = [:]
        recapListeners = [:]
        previewsByHapp = [:]
        recapsByHapp = [:]
    }

    // MARK: Safe views of the data (blocked people, hidden photos, filtered captions)
    
    /// Hide key for a recap: its storage path with "/" replaced, which is unique per photo.
    static func hideID(for recap: Recap) -> String { ReportTarget.safeID(recap.storagePath) }
    
    func visibleRecaps(_ happID: String) -> [Recap] {
        (recapsByHapp[happID] ?? []).filter {
            !blockedIDs.contains($0.authorID) && !hiddenIDs.contains(Self.hideID(for: $0))
        }
    }
    
    func visiblePreviews(_ happID: String) -> [RecapPreview] {
        (previewsByHapp[happID] ?? []).filter { !blockedIDs.contains($0.authorID) }
    }
    
    // MARK: Writes

    /// Uploads each photo, then writes both Firestore documents in one batch.
    /// If the batch fails the uploaded file is deleted again.
    func post(
        happID: String,
        userID: String,
        authorName: String,
        drafts: [RecapDraft],
        notify: RecapAudience? = nil
    ) async throws {
        for draft in drafts { try ContentFilter.validate(draft.caption, field: "caption") }
        let base = db.collection("happs").document(happID)
        let mine = try await base.collection("recaps")
            .whereField("authorID", isEqualTo: userID)
            .getDocuments()
        let slots = RecapRules.freeSlots(userID: userID, existingIDs: mine.documents.map(\.documentID))
        guard drafts.count <= slots.count else { throw RecapError.tooMany }

        for (draft, slot) in zip(drafts, slots) {
            let path = Recap.makePath(happID: happID, userID: userID)
            try await storage.upload(draft.full, to: path)
            do {
                let docID = RecapRules.slotID(userID: userID, slot: slot)
                let batch = db.batch()
                batch.setData([
                    "authorID": userID,
                    "authorName": authorName,
                    "storagePath": path,
                    "caption": String(draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140)),
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: base.collection("recaps").document(docID))
                batch.setData([
                    "authorID": userID,
                    "imageData": draft.preview,
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: base.collection("recapPreviews").document(docID))
                try await batch.commit()
            } catch {
                try? await storage.remove(path)
                throw error
            }
        }

        if let notify {
            let drafts = RecapNotifications.drafts(for: notify, authorID: userID, authorName: authorName, photoCount: drafts.count)
            await NotificationWriter(database: db).send(drafts, from: userID)
        }
    }

    /// Account deletion: removes every recap this user posted, wherever it is.
    func removeAll(forAuthor userID: String) async {
        guard let snapshot = try? await db.collectionGroup("recaps")
            .whereField("authorID", isEqualTo: userID).getDocuments() else { return }
        for document in snapshot.documents {
            let batch = db.batch()
            batch.deleteDocument(document.reference)
            if let previews = document.reference.parent.parent?.collection("recapPreviews") {
                batch.deleteDocument(previews.document(document.documentID))
            }
            if let path = document.data()["storagePath"] as? String {
                try? await storage.remove(path)
            }
            try? await batch.commit()
        }
    }

    func delete(_ recap: Recap) async {
        let base = db.collection("happs").document(recap.happID)
        let batch = db.batch()
        batch.deleteDocument(base.collection("recaps").document(recap.id))
        batch.deleteDocument(base.collection("recapPreviews").document(recap.id))
        do {
            try await batch.commit()
            try? await storage.remove(recap.storagePath)
        } catch {
            errorMessage = RecapError.message(for: error)
        }
    }

    private func log(_ error: Error) {
        #if DEBUG
        print("RecapStore listener error: \(error)")
        #endif
    }
}

