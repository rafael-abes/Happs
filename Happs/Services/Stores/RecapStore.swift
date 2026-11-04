//
//  RecapStore.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//
//  CODE OVERVIEW
//  -------------
//  Store for event recaps (photos posted after a Happ). ObservableObject model used by the Happs feed and the
//  recap screens; views never call Firestore or Supabase directly.
//  Data layout: happs/{id}/recaps holds full records (attendees only); happs/{id}/recapPreviews holds a small
//  preview image any signed-in user can see. Both documents use the same id (a per-user slot id) and are
//  always written and deleted together in one batch so they cannot drift apart.
//  The full image goes to Supabase storage, only its path is kept in Firestore. One snapshot listener per Happ
//  is kept in a dictionary and removed when no longer needed.
//  blockedIDs and hiddenIDs are filtered at read time (visibleRecaps / visiblePreviews), so nothing is deleted.
//
import Foundation
import FirebaseFirestore
import Combine

/// One photo the user has picked but not posted yet.
struct RecapDraft: Identifiable {
    let id = UUID()
    /// Full-size image bytes (uploaded to storage).
    let full: Data
    /// Small image bytes stored in Firestore for the preview strip.
    let preview: Data
    var caption = ""
}

/// Owns the recap listeners and writes. Views never touch Firestore or Supabase directly.
@MainActor
final class RecapStore: ObservableObject {
    /// Previews per Happ id, from the recapPreviews listeners. Use visiblePreviews to get the filtered list.
    @Published private(set) var previewsByHapp: [String: [RecapPreview]] = [:]
    /// Full recaps per Happ id, from the recaps listeners. Use visibleRecaps to get the filtered list.
    @Published private(set) var recapsByHapp: [String: [Recap]] = [:]
    /// Message for the UI after a failed delete.
    @Published var errorMessage: String?
    /// Set from ContentView (SafetyStore).
    @Published var blockedIDs: Set<String> = []
    /// hiddenIDs holds ids of individual photos the user has hidden (see hideID). Both sets are applied only when reading, nothing is deleted.
    @Published var hiddenIDs: Set<String> = []

    /// Computed so each use gets the current Firestore instance.
    private var db: Firestore { Firestore.firestore() }
    /// Supabase wrapper that holds the actual photo files.
    private let storage = SupabaseStorageService.shared
    /// One live listener per Happ id; the dictionary stops duplicate listeners and lets them be removed individually.
    private var previewListeners: [String: ListenerRegistration] = [:]
    private var recapListeners: [String: ListenerRegistration] = [:]

    // MARK: Previews (any signed-in user)

    /// Keeps exactly these Happs' previews live. Used by the Happs feed.
    func observePreviews(for happIDs: [String]) {
        let wanted = Set(happIDs)
        // Remove listeners for Happs that left the feed, so they stop costing reads.
        for id in Array(previewListeners.keys) where !wanted.contains(id) {
            previewListeners[id]?.remove()
            previewListeners[id] = nil
            previewsByHapp[id] = nil
        }
        // ensurePreviews skips ids that already have a listener.
        for id in wanted { ensurePreviews(happID: id) }
    }

    /// Adds one Happ's preview listener without touching the others.
    func ensurePreviews(happID: String) {
        guard previewListeners[happID] == nil else { return }
        // Subcollection listener: fires once with existing data, then on every change.
        previewListeners[happID] = db.collection("happs").document(happID)
            .collection("recapPreviews")
            // [weak self] avoids a retain cycle. This closure has no Task { @MainActor }, so it relies on the
            // listener callback being delivered on the main queue (Firestore's default) (assumed reason).
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.log(error); return }
                // Build model objects from raw dictionaries; documents that fail to parse (nil) are skipped.
                let items = snapshot?.documents.compactMap {
                    RecapPreview(id: $0.documentID, happID: happID, data: $0.data())
                } ?? []
                // Oldest first for the preview strip.
                self.previewsByHapp[happID] = items.sorted { $0.createdAt < $1.createdAt }
            }
    }

    // MARK: Recaps (attendees only)

    /// Starts the full-recap listener for one Happ. Only attendees can read this collection (enforced by Firestore rules,
    /// assumed from the section name), so call it only for attendees.
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
                // Newest first for the full recap list.
                self.recapsByHapp[happID] = items.sorted { $0.createdAt > $1.createdAt }
            }
    }

    /// Stops one Happ's recap listener, for example when its screen closes.
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
    
    /// Recaps for a Happ with blocked authors and individually hidden photos removed.
    func visibleRecaps(_ happID: String) -> [Recap] {
        (recapsByHapp[happID] ?? []).filter {
            !blockedIDs.contains($0.authorID) && !hiddenIDs.contains(Self.hideID(for: $0))
        }
    }
    
    /// Previews for a Happ with blocked authors removed.
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
        // Reject a bad caption before any upload. Steps: 1) validate captions, 2) check free slots, 3) upload file, 4) write both documents in a batch,
        // 5) send notifications. The ordering keeps bad input from ever reaching the network.
        for draft in drafts { try ContentFilter.validate(draft.caption, field: "caption") }
        let base = db.collection("happs").document(happID)
        // Existing recaps by this user, to work out how many photo slots are still free.
        let mine = try await base.collection("recaps")
            .whereField("authorID", isEqualTo: userID)
            .getDocuments()
        // RecapRules decides which slot ids are free (a per-user cap on photos); too many drafts throws tooMany.
        let slots = RecapRules.freeSlots(userID: userID, existingIDs: mine.documents.map(\.documentID))
        guard drafts.count <= slots.count else { throw RecapError.tooMany }

        for (draft, slot) in zip(drafts, slots) {
            // The path is unique per photo; the upload is done first, then the Firestore write.
            let path = Recap.makePath(happID: happID, userID: userID)
            try await storage.upload(draft.full, to: path)
            do {
                // Slot id is reused for both documents so recap and preview stay paired.
                let docID = RecapRules.slotID(userID: userID, slot: slot)
                let batch = db.batch()
                batch.setData([
                    "authorID": userID,
                    "authorName": authorName,
                    "storagePath": path,
                    // Trimmed and cut to 140 characters.
                    "caption": String(draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140)),
                    // serverTimestamp lets the server set the time, so it does not depend on the phone clock.
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: base.collection("recaps").document(docID))
                batch.setData([
                    "authorID": userID,
                    "imageData": draft.preview,
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: base.collection("recapPreviews").document(docID))
                // Both documents commit together or not at all.
                try await batch.commit()
            } catch {
                // Roll back the uploaded file so a failed batch does not leave an orphan in storage, then rethrow.
                try? await storage.remove(path)
                throw error
            }
        }

        // Best effort: NotificationWriter.send does not throw, so notification failure cannot fail the post.
        if let notify {
            let drafts = RecapNotifications.drafts(for: notify, authorID: userID, authorName: authorName, photoCount: drafts.count)
            await NotificationWriter(database: db).send(drafts, from: userID)
        }
    }

    /// Account deletion: removes every recap this user posted, wherever it is.
    /// Deletes this user's recaps, previews and files across all Happs. Uses collectionGroup("recaps") to
    /// query every Happ's recaps subcollection at once, matched by authorID. Failures are ignored (`try?`)
    /// so deletion carries on with the rest.
    func removeAll(forAuthor userID: String) async {
        guard let snapshot = try? await db.collectionGroup("recaps")
            .whereField("authorID", isEqualTo: userID).getDocuments() else { return }
        for document in snapshot.documents {
            let batch = db.batch()
            batch.deleteDocument(document.reference)
            // parent.parent is the Happ document; its recapPreviews subcollection has the paired document.
            if let previews = document.reference.parent.parent?.collection("recapPreviews") {
                batch.deleteDocument(previews.document(document.documentID))
            }
            if let path = document.data()["storagePath"] as? String {
                try? await storage.remove(path)
            }
            try? await batch.commit()
        }
    }

    /// Deletes one recap (both Firestore documents in a batch), then its file. The file is only removed
    /// after the batch succeeds, so a failed delete does not leave a recap pointing at a missing image.
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

    /// Debug-only logging for listener errors.
    private func log(_ error: Error) {
        #if DEBUG
        print("RecapStore listener error: \(error)")
        #endif
    }
}


