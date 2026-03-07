//
//  SummaryService.swift
//  MeetingScribe
//

import Foundation

protocol SummaryServiceProtocol: Sendable {
    func summarize(transcript: String, modelID: String) async throws -> String
}

/// Placeholder. Ollama API integration will be added in 開発手順 5.
final class SummaryService: SummaryServiceProtocol {
    func summarize(transcript: String, modelID: String) async throws -> String {
        // TODO: Call Ollama API
        ""
    }
}
