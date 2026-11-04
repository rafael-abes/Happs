//
//  SupabaseStorageService.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//


// CODE OVERVIEW
// Wraps the Supabase Storage SDK for recap photos. Firestore holds the Happ data, Supabase only
// holds the image files (assumed reason: a free storage tier). The user is already signed in with
// Firebase, so the Supabase client is given the Firebase ID token as its access token, letting
// Supabase bucket policies identify the caller without a second login. The service is a singleton
// on the main actor and creates its client lazily. RecapImageLoader downloads photos through
// short-lived signed URLs (the bucket is not public) and caches them in memory.
//
import Foundation
import UIKit
import Supabase
import FirebaseAuth

/// All Supabase Storage calls. The client sends the user's Firebase ID token with every
/// request, so the bucket policies can see who is asking.
/// Needs in Secrets.swift: supabaseURL (String) and supabaseAnonKey (String).
@MainActor
final class SupabaseStorageService {
    /// Single shared instance; the private init stops other copies being made.
    static let shared = SupabaseStorageService()

    /// Name of the Supabase Storage bucket that holds recap photos.
    private let bucket = "recaps"
    /// Created on first use and then reused, so the keys are only checked once.
    private var cachedClient: SupabaseClient?

    private init() {}

    /// Lazily builds the Supabase client. Throws RecapError.notConfigured if the URL is invalid or the
    /// key is still the placeholder text.
    private func client() throws -> SupabaseClient {
        if let cachedClient { return cachedClient }
        guard let url = URL(string: Secrets.supabaseURL),
              !Secrets.supabaseAnonKey.hasPrefix("PASTE") else {
            throw RecapError.notConfigured
        }
        let created = SupabaseClient(
            supabaseURL: url,
            supabaseKey: Secrets.supabaseAnonKey,
            options: SupabaseClientOptions(
                // Called by the SDK whenever it needs a token, so a fresh Firebase ID token is fetched each time (Firebase refreshes it when expired).
                auth: .init(accessToken: {
                    try await Auth.auth().currentUser?.getIDToken()
                })
            )
        )
        cachedClient = created
        return created
    }

    /// Uploads JPEG bytes to the given path in the bucket.
    func upload(_ data: Data, to path: String) async throws {
        _ = try await client().storage
            .from(bucket)
            // upsert false means uploading to an existing path fails instead of overwriting someone's photo.
            .upload(path, data: data, options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: false))
    }

    /// Makes a temporary download link for a private file (valid for `seconds`, default one hour).
    func signedURL(for path: String, expiresIn seconds: Int = 3600) async throws -> URL {
        try await client().storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: seconds)
    }

    /// Deletes one file from the bucket.
    func remove(_ path: String) async throws {
        _ = try await client().storage
            .from(bucket)
            .remove(paths: [path])
    }

    /// F0 check: upload, sign, download and delete one tiny file. Returns a readable log.
    func selfTest() async -> String {
        guard let uid = Auth.auth().currentUser?.uid else { return "Sign in first." }
        // Stored under the user's own uid folder (assumed reason: so the bucket policy allows it).
        let path = "selftest/\(uid)/test.jpg"
        let sample = ImageProcessor.sampleJPEG()
        var log: [String] = []
        do {
            try await upload(sample, to: path)
            log.append("1. Upload OK (\(sample.count) bytes)")
            let url = try await signedURL(for: path, expiresIn: 60)
            log.append("2. Signed URL OK")
            let (data, response) = try await URLSession.shared.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            log.append("3. Download status \(code), \(data.count) bytes")
            try await remove(path)
            log.append("4. Delete OK")
            log.append(code == 200 && data.count == sample.count ? "PASS" : "FAIL: size or status mismatch")
        } catch {
            log.append("FAILED: \(error)")
            // Best effort cleanup of the test file after a failure.
            try? await remove(path)
        }
        return log.joined(separator: "\n")
    }
}

/// Downloads a photo through a fresh signed URL and keeps it in memory.
// A separate class so UI code can ask for an image by path without knowing about signed URLs.
@MainActor
final class RecapImageLoader {
    static let shared = RecapImageLoader()
    /// In-memory cache keyed by storage path. NSCache evicts automatically under memory pressure.
    private let cache = NSCache<NSString, UIImage>()
    private init() {}

    /// Returns the cached image, or downloads it via a fresh signed URL. Throws RecapError.badImage on a non-200 or undecodable response.
    func image(for path: String) async throws -> UIImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let url = try await SupabaseStorageService.shared.signedURL(for: path)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { throw RecapError.badImage }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
