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

    // MARK: Writes

    /// Uploads each photo, then writes both Firestore documents in one batch.
    /// If the batch fails the uploaded file is deleted again.
    func post(happID: String, userID: String, authorName: String, drafts: [RecapDraft]) async throws {
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

