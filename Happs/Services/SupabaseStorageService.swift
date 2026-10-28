//
//  SupabaseStorageService.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
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
    static let shared = SupabaseStorageService()

    private let bucket = "recaps"
    private var cachedClient: SupabaseClient?

    private init() {}

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
                auth: .init(accessToken: {
                    try await Auth.auth().currentUser?.getIDToken()
                })
            )
        )
        cachedClient = created
        return created
    }

    func upload(_ data: Data, to path: String) async throws {
        _ = try await client().storage
            .from(bucket)
            .upload(path, data: data, options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: false))
    }

    func signedURL(for path: String, expiresIn seconds: Int = 3600) async throws -> URL {
        try await client().storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: seconds)
    }

    func remove(_ path: String) async throws {
        _ = try await client().storage
            .from(bucket)
            .remove(paths: [path])
    }

    /// F0 check: upload, sign, download and delete one tiny file. Returns a readable log.
    func selfTest() async -> String {
        guard let uid = Auth.auth().currentUser?.uid else { return "Sign in first." }
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
            try? await remove(path)
        }
        return log.joined(separator: "\n")
    }
}

/// Downloads a photo through a fresh signed URL and keeps it in memory.
@MainActor
final class RecapImageLoader {
    static let shared = RecapImageLoader()
    private let cache = NSCache<NSString, UIImage>()
    private init() {}

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
