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
        guard let outputDir = await settings.outputDirectoryURL else { return }
        let fileManager = FileManager.default
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension

        // 1. 文字起こし → 完了次第すぐにファイル出力
        let modelID = await settings.selectedWhisperModelID ?? "default"
        let transcript = try await transcription.transcribe(audioOrVideoURL: fileURL, modelID: modelID)

        let recordingDestURL = outputDir.appendingPathComponent("\(baseName).\(ext)")
        let samePath = fileURL.standardizedFileURL.path == recordingDestURL.standardizedFileURL.path
        if !samePath {
            if fileManager.fileExists(atPath: recordingDestURL.path) {
                try fileManager.removeItem(at: recordingDestURL)
            }
            try fileManager.copyItem(at: fileURL, to: recordingDestURL)
        }

        let transcriptURL = outputDir.appendingPathComponent("\(baseName)_transcript.md")
        let markdownTranscript = "# 文字起こし\n\n\(transcript)"
        try markdownTranscript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        // 2. 要約（設定があれば）→ 完了次第すぐにファイル出力
        if let summaryModelID = await settings.selectedSummaryModelID, !summaryModelID.isEmpty {
            let summaryText = try await summary.summarize(transcript: transcript, modelID: summaryModelID)
            let summaryURL = outputDir.appendingPathComponent("\(baseName)_summary.md")
            let markdownSummary = "# 要約\n\n\(summaryText)"
            try markdownSummary.write(to: summaryURL, atomically: true, encoding: .utf8)
        }
    }
}
