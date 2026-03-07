//
//  TranscriptionService.swift
//  MeetingScribe
//

import Foundation

protocol TranscriptionServiceProtocol: Sendable {
    func transcribe(audioOrVideoURL: URL, modelID: String) async throws -> String
}

/// Placeholder. Whisper (bundled binary) integration will be added in 開発手順 4.
final class TranscriptionService: TranscriptionServiceProtocol {
    func transcribe(audioOrVideoURL: URL, modelID: String) async throws -> String {
        // TODO: Run bundled whisper binary with model at Application Support
        ""
    }
}
