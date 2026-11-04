//
//  AIService.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//

//  CODE OVERVIEW
//  -------------
//  Talks to Google's Gemini model through Firebase AI Logic and returns a JSON string describing a Happ.
//  HappIntentGenerating is a protocol, so the parser can be unit tested with a fake instead of the network.
//  AIService (the real implementation) is an ObservableObject so views can react to the kill switch and model
//  name, both read from Firebase Remote Config. This lets them be changed without an app update.
//  The model is forced to answer in JSON that matches a Schema at low temperature, so output is predictable
//  and easy to parse. AIError.classify turns any thrown error into a small set of user-friendly cases.
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

/// Errors the assistant can show to the user. Equatable so tests can compare them directly.
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

    /// Message shown in the UI for each case.
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
    /// Maps any thrown error to one of our cases. Pure, so it is unit tested.
    static func classify(_ error: Error) -> AIError {
        // Already one of ours, pass it through.
        if let known = error as? AIError { return known }
        // A cancelled Swift task is not a failure.
        if error is CancellationError { return .cancelled }
        // Network-level failures are checked by code first, because that is reliable.
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
        // For SDK errors with no stable type, fall back to searching the error text (case-insensitive). This is fragile if wording changes (assumed trade-off).
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

/// Real implementation that calls Gemini. @MainActor so its published state is changed on the main thread.
@MainActor
final class AIService: ObservableObject, HappIntentGenerating {
    /// Used when Remote Config gives no model name.
    static let defaultModelName = "gemini-3.5-flash-lite"

    /// Kill switch. The editor hides "Describe it" when this is false.
    @Published private(set) var isEnabled = true
    /// Model id currently in use.
    @Published private(set) var modelName = AIService.defaultModelName

    /// Category names the model may choose from; must match the app's categories.
    private static let categoryNames = ["Food", "Sport", "Study", "Happs"]

    /// Reads model name and kill switch from Remote Config when that package is linked.
    /// Defaults apply when it is not, or when the fetch fails.
    func refreshConfig() async {
        // canImport guard: the file still compiles if the Remote Config package is not linked.
        #if canImport(FirebaseRemoteConfig)
        let remote = RemoteConfig.remoteConfig()
        // Defaults first, so the app has values before any fetch succeeds.
        remote.setDefaults([
            "ai_model_name": Self.defaultModelName as NSString,
            "ai_enabled": true as NSNumber
        ])
        do {
            // fetchAndActivate downloads values and makes them live. Failures only log, defaults stay.
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

    /// Sends the prompt to Gemini and returns the JSON text.
    /// - Throws: AIError (any other error is converted by `classify`).
    func generateIntentJSON(system: String, prompt: String) async throws -> String {
        // Kill switch: refuse before any network call.
        guard isEnabled else { throw AIError.disabled }
        // A model is built per call so it uses the current model name and the given system prompt.
        let model = makeModel(system: system)
        do {
            let response = try await model.generateContent(prompt)
            guard let text = response.text, !text.isEmpty else { throw AIError.badResponse }
            return text
        // Everything thrown is mapped to AIError, including the badResponse above.
        } catch {
            throw AIError.classify(error)
        }
    }

    /// Builds the Gemini model with a response schema, so the reply is JSON with these fields.
    private func makeModel(system: String) -> GenerativeModel {
        // Schema describes the JSON the model must produce; `category` is limited to the four names.
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
            // Only title is required; the others may be missing (the model lists what it could not find in missingFields).
            optionalProperties: [
                "category", "locationText", "startLocal", "durationMinutes",
                "inviteGroupText", "notes", "missingFields"
            ]
        )
        // Low temperature = less random, which suits extracting facts. Token cap keeps replies short and cheap.
        let config = GenerationConfig(
            temperature: 0.1,
            maxOutputTokens: 400,
            responseMIMEType: "application/json",
            responseSchema: schema
        )
        // .googleAI() selects the Gemini Developer API backend through Firebase AI Logic (rather than Vertex AI).
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        return ai.generativeModel(
            modelName: modelName,
            generationConfig: config,
            systemInstruction: ModelContent(role: "system", parts: system)
        )
    }
}
