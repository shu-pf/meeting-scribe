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
        let startedAt = Date()
        let modelID = await settings.selectedWhisperModelID ?? "default"
        let transcript = try await transcription.transcribe(audioOrVideoURL: fileURL, modelID: modelID)
        let summaryText: String?
        if let summaryModelID = await settings.selectedSummaryModelID, !summaryModelID.isEmpty {
            summaryText = try await summary.summarize(transcript: transcript, modelID: summaryModelID)
        } else {
            summaryText = nil
        }
        let endedAt = Date()
        let result = RecordingResult(
            fileURL: fileURL,
            startedAt: startedAt,
            endedAt: endedAt,
            transcript: transcript,
            summaryText: summaryText
        )
        guard let outputDir = await settings.outputDirectoryURL else { return }
        let fileManager = FileManager.default
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension
        let recordingDestURL = outputDir.appendingPathComponent("\(baseName).\(ext)")
        let samePath = fileURL.standardizedFileURL.path == recordingDestURL.standardizedFileURL.path
        if !samePath {
            if fileManager.fileExists(atPath: recordingDestURL.path) {
                try fileManager.removeItem(at: recordingDestURL)
            }
            try fileManager.copyItem(at: fileURL, to: recordingDestURL)
        }
        let transcriptURL = outputDir.appendingPathComponent("\(baseName)_transcript.md")
        let summaryURL = outputDir.appendingPathComponent("\(baseName)_summary.md")
        if let t = result.transcript {
            let markdown = "# 文字起こし\n\n\(t)"
            try markdown.write(to: transcriptURL, atomically: true, encoding: .utf8)
        }
        if let s = result.summaryText {
            let markdown = "# 要約\n\n\(s)"
            try markdown.write(to: summaryURL, atomically: true, encoding: .utf8)
        }
    }
}
