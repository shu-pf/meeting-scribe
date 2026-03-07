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
        if fileManager.fileExists(atPath: recordingDestURL.path) {
            try fileManager.removeItem(at: recordingDestURL)
        }
        try fileManager.copyItem(at: fileURL, to: recordingDestURL)
        let transcriptURL = outputDir.appendingPathComponent("\(baseName)_transcript.txt")
        let summaryURL = outputDir.appendingPathComponent("\(baseName)_summary.txt")
        if let t = result.transcript {
            try t.write(to: transcriptURL, atomically: true, encoding: .utf8)
        }
        if let s = result.summaryText {
            try s.write(to: summaryURL, atomically: true, encoding: .utf8)
        }
    }
}
