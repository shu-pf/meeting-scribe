//
//  RecordingPipeline.swift
//  MeetingScribe
//

import Foundation

protocol RecordingPipelineProtocol: Sendable {
    func processRecording(fileURL: URL) async throws
}

final class RecordingPipeline: RecordingPipelineProtocol {
    private static let baseNameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

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
        guard let outputDir = await settings.outputDirectoryURL else { return }
        let fileManager = FileManager.default
        let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension

        // 1. 文字起こし
        let modelID = await settings.selectedWhisperModelID ?? "default"
        let transcript = try await transcription.transcribe(audioOrVideoURL: fileURL, modelID: modelID)

        // 2. 要約（設定があれば）→ タイトル取得。なければ「無題」
        let meetingTitle: String
        var summaryResult: SummarizeResult?
        if let summaryModelID = await settings.selectedSummaryModelID, !summaryModelID.isEmpty {
            let result = try await summary.summarize(transcript: transcript, modelID: summaryModelID)
            summaryResult = result
            meetingTitle = result.title
        } else {
            meetingTitle = "無題"
        }

        // 3. 日時 + 会議名で baseName を生成
        let recordingDate = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.creationDate] as? Date) ?? Date()
        let dateString = Self.baseNameDateFormatter.string(from: recordingDate)
        let sanitizedTitle = Self.sanitizeFileName(meetingTitle)
        let baseName = "\(dateString)_\(sanitizedTitle)"

        // 4. 録画を outputDir にコピー
        let recordingDestURL = outputDir.appendingPathComponent("\(baseName).\(ext)")
        let samePath = fileURL.standardizedFileURL.path == recordingDestURL.standardizedFileURL.path
        if !samePath {
            if fileManager.fileExists(atPath: recordingDestURL.path) {
                try fileManager.removeItem(at: recordingDestURL)
            }
            try fileManager.copyItem(at: fileURL, to: recordingDestURL)
        }

        // 5. 文字起こしを出力
        let transcriptURL = outputDir.appendingPathComponent("\(baseName)_transcript.md")
        let markdownTranscript = "# 文字起こし\n\n\(transcript)"
        try markdownTranscript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        // 6. 要約を出力（先頭に会議名を明示）
        if let result = summaryResult {
            let summaryURL = outputDir.appendingPathComponent("\(baseName)_summary.md")
            let markdownSummary = "# 要約\n\n## 会議名\n\(result.title)\n\n\(result.body)"
            try markdownSummary.write(to: summaryURL, atomically: true, encoding: .utf8)
        }
    }

    /// ファイル名に使えない文字をアンダースコアに置換し、長さを制限する
    private static func sanitizeFileName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }
        let joined = components.joined()
        let collapsed = joined.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        let result = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if result.isEmpty { return "無題" }
        return String(result.prefix(80))
    }
}
