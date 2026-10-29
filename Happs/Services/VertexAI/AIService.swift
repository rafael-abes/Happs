//
//  AIService.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//

import Foundation
import Combine
import FirebaseAILogic
#if canImport(FirebaseRemoteConfig)
import FirebaseRemoteConfig
#endif

/// Anything that can turn (system, prompt) into a JSON string. Tests use a fake.
@MainActor
protocol HappIntentGenerating {
    func generateIntentJSON(system: String, prompt: String) async throws -> String
}

enum AIError: Error, Equatable, LocalizedError {
    case quotaExceeded
    case appCheck
    case offline
    case badResponse
    case disabled
    case dailyLimit
    case emptyInput
    case cancelled
    case unknown

    var errorDescription: String? {
        switch self {
        case .quotaExceeded: return "The assistant is busy right now. Try again in a minute, or fill the form by hand."
        case .appCheck: return "Couldn't verify this app with the server. Try again later."
        case .offline: return "You seem to be offline. Check your connection and try again."
        case .badResponse: return "I couldn't understand the answer. Try rephrasing."
        case .disabled: return "The assistant is switched off for now."
        case .dailyLimit: return "You've reached today's assistant limit. It resets tomorrow."
        case .emptyInput: return "Type or say what you want to organise."
        case .cancelled: return "Cancelled."
        case .unknown: return "Something went wrong. Try again, or fill the form by hand."
        }
    }

    /// Maps any thrown error to one of our cases. Pure, so it is unit tested.
    static func classify(_ error: Error) -> AIError {
        if let known = error as? AIError { return known }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
                return .offline
            case .cancelled:
                return .cancelled
            default:
                break
            }
        }
        let text = (String(describing: error) + " " + error.localizedDescription).lowercased()
        if text.contains("429") || text.contains("quota") || text.contains("resource_exhausted")
            || text.contains("resource exhausted") || text.contains("rate limit") {
            return .quotaExceeded
        }
        if text.contains("app check") || text.contains("appcheck") || text.contains("attestation") {
            return .appCheck
        }
        if text.contains("offline") || text.contains("internet connection") {
            return .offline
        }
        return .unknown
    }
}

@MainActor
final class AIService: ObservableObject, HappIntentGenerating {
    static let defaultModelName = "gemini-3.5-flash-lite"

    /// Kill switch. The editor hides "Describe it" when this is false.
    @Published private(set) var isEnabled = true
    @Published private(set) var modelName = AIService.defaultModelName

    private static let categoryNames = ["Food", "Sport", "Study", "Happs"]

    /// Reads model name and kill switch from Remote Config when that package is linked.
    /// Defaults apply when it is not, or when the fetch fails.
    func refreshConfig() async {
        #if canImport(FirebaseRemoteConfig)
        let remote = RemoteConfig.remoteConfig()
        remote.setDefaults([
            "ai_model_name": Self.defaultModelName as NSString,
            "ai_enabled": true as NSNumber
        ])
        do {
            _ = try await remote.fetchAndActivate()
        } catch {
            #if DEBUG
            print("Remote Config fetch failed: \(error)")
            #endif
        }
        let name = remote["ai_model_name"].stringValue
        modelName = name.isEmpty ? Self.defaultModelName : name
        isEnabled = remote["ai_enabled"].boolValue
        #endif
    }

    func generateIntentJSON(system: String, prompt: String) async throws -> String {
        guard isEnabled else { throw AIError.disabled }
        let model = makeModel(system: system)
        do {
            let response = try await model.generateContent(prompt)
            guard let text = response.text, !text.isEmpty else { throw AIError.badResponse }
            return text
        } catch {
            throw AIError.classify(error)
        }
    }

    private func makeModel(system: String) -> GenerativeModel {
        let schema = Schema.object(
            properties: [
                "title": .string(),
                "category": .enumeration(values: Self.categoryNames),
                "locationText": .string(),
                "startLocal": .string(),
                "durationMinutes": .integer(),
                "inviteGroupText": .string(),
                "notes": .string(),
                "missingFields": .array(items: .string())
            ],
            optionalProperties: [
                "category", "locationText", "startLocal", "durationMinutes",
                "inviteGroupText", "notes", "missingFields"
            ]
        )
        let config = GenerationConfig(
            temperature: 0.1,
            maxOutputTokens: 400,
            responseMIMEType: "application/json",
            responseSchema: schema
        )
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        return ai.generativeModel(
            modelName: modelName,
            generationConfig: config,
            systemInstruction: ModelContent(role: "system", parts: system)
        )
    }
}
