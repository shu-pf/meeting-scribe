//
//  RecordingPipeline.swift
//  MeetingScribe
//

import Foundation

protocol RecordingPipelineProtocol: Sendable {
    func processRecording(fileURL: URL) async throws
}

final class RecordingPipeline: RecordingPipelineProtocol {
    private let transcription: TranscriptionServiceProtocol
    private let summary: SummaryServiceProtocol
    private let settings: SettingsServiceProtocol

    init(
        transcription: TranscriptionServiceProtocol,
        summary: SummaryServiceProtocol,
        settings: SettingsServiceProtocol
    ) {
        self.transcription = transcription
        self.summary = summary
        self.settings = settings
    }

    func processRecording(fileURL: URL) async throws {
        let modelID = await settings.selectedWhisperModelID ?? "default"
        let transcript = try await transcription.transcribe(audioOrVideoURL: fileURL, modelID: modelID)
        let summaryModelID = await settings.selectedSummaryModelID ?? "default"
        let summaryText = try await summary.summarize(transcript: transcript, modelID: summaryModelID)
        guard let outputDir = await settings.outputDirectoryURL else { return }
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let transcriptURL = outputDir.appendingPathComponent("\(baseName)_transcript.txt")
        let summaryURL = outputDir.appendingPathComponent("\(baseName)_summary.txt")
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
        try summaryText.write(to: summaryURL, atomically: true, encoding: .utf8)
    }
}
