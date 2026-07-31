//
//  RecordingPipeline.swift
//  MeetingScribe
//

import Foundation

/// パイプラインの処理結果
struct PipelineResult: Sendable {
    /// 要約モデルが生成した会議タイトル
    let meetingTitle: String
    let recordingURL: URL
    let transcriptURL: URL
    let summaryURL: URL
}

struct PipelineRequest: Sendable {
    let id: UUID
    let fileURL: URL
    let outputDirectoryURL: URL
    let recordingDate: Date
    let whisperModelID: String
    let summaryModelID: String
}

/// 保存済みの文字起こしから要約だけをやり直す要求
struct ResummarizeRequest: Sendable {
    let id: UUID
    let recordingURL: URL
    let transcriptURL: URL
    /// やり直し前の要約ファイル。新しい名前と異なる場合は片付ける。
    let existingSummaryURL: URL?
    let outputDirectoryURL: URL
    let recordingDate: Date
    let summaryModelID: String
}

private struct PipelineSummaryCheckpoint: Codable {
    let result: SummarizeResult
    let baseName: String
}

/// 録画後パイプラインの進捗
enum PipelineProgress: Sendable {
    case transcribing
    case summarizing
    case saving
}

protocol RecordingPipelineProtocol: Sendable {
    @discardableResult
    func processRecording(
        request: PipelineRequest,
        onProgress: @escaping @Sendable (PipelineProgress) async -> Void
    ) async throws -> PipelineResult

    @discardableResult
    func resummarize(
        request: ResummarizeRequest,
        onProgress: @escaping @Sendable (PipelineProgress) async -> Void
    ) async throws -> PipelineResult
}

final class RecordingPipeline: RecordingPipelineProtocol {
    private let diagnosticLog = DiagnosticLogger(category: "Pipeline")
    private static let transcriptHeading = "# 文字起こし\n\n"

    private static let baseNameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private let transcription: TranscriptionServiceProtocol
    private let summary: SummaryServiceProtocol
    init(
        transcription: TranscriptionServiceProtocol,
        summary: SummaryServiceProtocol
    ) {
        self.transcription = transcription
        self.summary = summary
    }

    @discardableResult
    func processRecording(
        request: PipelineRequest,
        onProgress: @escaping @Sendable (PipelineProgress) async -> Void
    ) async throws -> PipelineResult {
        let fileURL = request.fileURL
        let outputDir = request.outputDirectoryURL
        diagnosticLog.info("パイプライン処理開始 fileURL=\(fileURL.path)")
        let fileManager = FileManager.default
        let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let workDirectory = try PipelineWorkspace.workDirectory(for: request.id)
        try fileManager.createDirectory(
            at: workDirectory,
            withIntermediateDirectories: true
        )
        let transcriptCheckpointURL = workDirectory
            .appendingPathComponent("transcript")
            .appendingPathExtension("txt")
        let summaryCheckpointURL = workDirectory
            .appendingPathComponent("summary")
            .appendingPathExtension("json")

        // 1. 文字起こし
        await onProgress(.transcribing)
        guard !request.whisperModelID.isEmpty else {
            throw RecordingPipelineError.whisperModelNotSelected
        }
        let transcript: String
        if fileManager.fileExists(atPath: transcriptCheckpointURL.path) {
            transcript = try String(
                contentsOf: transcriptCheckpointURL,
                encoding: .utf8
            )
            diagnosticLog.info(
                "文字起こしチェックポイントから再開 characterCount=\(transcript.count)"
            )
        } else {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw RecordingPipelineError.recordingNotFound(fileURL.path)
            }
            diagnosticLog.info(
                "文字起こし開始 modelID=\(request.whisperModelID)"
            )
            transcript = try await transcription.transcribe(
                audioOrVideoURL: fileURL,
                modelID: request.whisperModelID,
                workingDirectory: workDirectory
            )
            try transcript.write(
                to: transcriptCheckpointURL,
                atomically: true,
                encoding: .utf8
            )
            diagnosticLog.info("文字起こし完了 characterCount=\(transcript.count)")
        }

        // 2. 文字起こしをすぐに出力（要約の前。日時のみのファイル名）
        let dateString = Self.baseNameDateFormatter.string(from: request.recordingDate)
        let earlyTranscriptURL = outputDir.appendingPathComponent(
            "\(dateString)_\(request.id.uuidString.prefix(8))_transcript.md"
        )
        let markdownTranscript = "\(Self.transcriptHeading)\(transcript)"
        try markdownTranscript.write(to: earlyTranscriptURL, atomically: true, encoding: .utf8)

        // 3. 要約 → タイトル取得
        guard !request.summaryModelID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw RecordingPipelineError.summaryModelNotSelected
        }
        await onProgress(.summarizing)
        let summaryCheckpoint: PipelineSummaryCheckpoint
        if fileManager.fileExists(atPath: summaryCheckpointURL.path) {
            summaryCheckpoint = try JSONDecoder().decode(
                PipelineSummaryCheckpoint.self,
                from: Data(contentsOf: summaryCheckpointURL)
            )
            diagnosticLog.info("要約チェックポイントから再開")
        } else {
            diagnosticLog.info(
                "要約開始 modelID=\(request.summaryModelID) characterCount=\(transcript.count)"
            )
            let summaryResult = try await summary.summarize(
                transcript: transcript,
                modelID: request.summaryModelID
            )
            let sanitizedTitle = Self.sanitizeFileName(summaryResult.title)
            let preferredBaseName = "\(dateString)_\(sanitizedTitle)"
            let baseName = Self.availableBaseName(
                preferredBaseName,
                sourceURL: fileURL,
                outputDirectory: outputDir,
                extension: ext,
                fileManager: fileManager
            )
            summaryCheckpoint = PipelineSummaryCheckpoint(
                result: summaryResult,
                baseName: baseName
            )
            try JSONEncoder().encode(summaryCheckpoint).write(
                to: summaryCheckpointURL,
                options: .atomic
            )
        }
        let summaryResult = summaryCheckpoint.result
        let meetingTitle = summaryResult.title
        diagnosticLog.info("要約完了")

        await onProgress(.saving)

        // 4. 要約完了時に確定した日時 + 会議名の baseName を使用
        let baseName = summaryCheckpoint.baseName

        // 5. 録画を完成名へ移動（同じ出力フォルダ内なので再コピーしない）
        let recordingDestURL = outputDir.appendingPathComponent("\(baseName).\(ext)")
        let samePath = fileURL.standardizedFileURL.path == recordingDestURL.standardizedFileURL.path
        if !samePath {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.moveItem(at: fileURL, to: recordingDestURL)
            } else if !fileManager.fileExists(atPath: recordingDestURL.path) {
                throw RecordingPipelineError.recordingNotFound(fileURL.path)
            }
        }

        // 6. チェックポイントから文字起こしを完成名で保存する
        let transcriptURL = outputDir.appendingPathComponent("\(baseName)_transcript.md")
        try markdownTranscript.write(
            to: transcriptURL,
            atomically: true,
            encoding: .utf8
        )

        // 7. 要約を出力（先頭に会議名を明示）
        let summaryURL = outputDir.appendingPathComponent("\(baseName)_summary.md")
        try Self.markdownSummary(for: summaryResult).write(
            to: summaryURL,
            atomically: true,
            encoding: .utf8
        )
        if earlyTranscriptURL.standardizedFileURL != transcriptURL.standardizedFileURL {
            try? fileManager.removeItem(at: earlyTranscriptURL)
        }

        diagnosticLog.info("パイプライン処理完了 baseName=\(baseName)")
        return PipelineResult(
            meetingTitle: meetingTitle,
            recordingURL: recordingDestURL,
            transcriptURL: transcriptURL,
            summaryURL: summaryURL
        )
    }

    /// 保存済みの文字起こしを再利用し、要約だけをやり直して会議名でファイルを付け替える。
    @discardableResult
    func resummarize(
        request: ResummarizeRequest,
        onProgress: @escaping @Sendable (PipelineProgress) async -> Void
    ) async throws -> PipelineResult {
        let fileManager = FileManager.default
        let outputDir = request.outputDirectoryURL
        diagnosticLog.info(
            "要約やり直し開始 recordingURL=\(request.recordingURL.path)"
                + " transcriptURL=\(request.transcriptURL.path)"
        )

        guard !request.summaryModelID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw RecordingPipelineError.summaryModelNotSelected
        }
        guard fileManager.fileExists(atPath: request.transcriptURL.path) else {
            throw RecordingPipelineError.transcriptNotFound(request.transcriptURL.path)
        }
        let markdownTranscript = try String(
            contentsOf: request.transcriptURL,
            encoding: .utf8
        )
        let transcript = Self.strippingTranscriptHeading(markdownTranscript)
        guard !transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw RecordingPipelineError.transcriptEmpty(request.transcriptURL.path)
        }

        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let workDirectory = try PipelineWorkspace.workDirectory(for: request.id)
        try fileManager.createDirectory(
            at: workDirectory,
            withIntermediateDirectories: true
        )
        let summaryCheckpointURL = workDirectory
            .appendingPathComponent("summary")
            .appendingPathExtension("json")

        await onProgress(.summarizing)
        let ext = request.recordingURL.pathExtension.isEmpty
            ? "mp4"
            : request.recordingURL.pathExtension
        let summaryCheckpoint: PipelineSummaryCheckpoint
        if fileManager.fileExists(atPath: summaryCheckpointURL.path) {
            summaryCheckpoint = try JSONDecoder().decode(
                PipelineSummaryCheckpoint.self,
                from: Data(contentsOf: summaryCheckpointURL)
            )
            diagnosticLog.info("要約チェックポイントから再開")
        } else {
            diagnosticLog.info(
                "要約開始 modelID=\(request.summaryModelID) characterCount=\(transcript.count)"
            )
            let summaryResult = try await summary.summarize(
                transcript: transcript,
                modelID: request.summaryModelID
            )
            // 既存ファイル名の日時部分を保ち、会議名だけを付け替える。
            let dateString = Self.baseNameDateString(
                recordingURL: request.recordingURL,
                recordingDate: request.recordingDate
            )
            let sanitizedTitle = Self.sanitizeFileName(summaryResult.title)
            let baseName = Self.availableBaseName(
                "\(dateString)_\(sanitizedTitle)",
                sourceURL: request.recordingURL,
                outputDirectory: outputDir,
                extension: ext,
                fileManager: fileManager
            )
            summaryCheckpoint = PipelineSummaryCheckpoint(
                result: summaryResult,
                baseName: baseName
            )
            try JSONEncoder().encode(summaryCheckpoint).write(
                to: summaryCheckpointURL,
                options: .atomic
            )
        }
        let summaryResult = summaryCheckpoint.result
        let baseName = summaryCheckpoint.baseName
        diagnosticLog.info("要約完了")

        await onProgress(.saving)

        // 録画を新しい会議名へ付け替える。録画が失われていても要約は残す。
        var recordingDestURL = outputDir.appendingPathComponent("\(baseName).\(ext)")
        if request.recordingURL.standardizedFileURL != recordingDestURL.standardizedFileURL {
            if fileManager.fileExists(atPath: request.recordingURL.path) {
                try fileManager.moveItem(at: request.recordingURL, to: recordingDestURL)
            } else if !fileManager.fileExists(atPath: recordingDestURL.path) {
                diagnosticLog.warning(
                    "やり直し対象の録画が見つからないため名前を変更しません path=\(request.recordingURL.path)"
                )
                recordingDestURL = request.recordingURL
            }
        }

        // 文字起こしも同じ会議名へ揃える。
        let transcriptURL = outputDir.appendingPathComponent("\(baseName)_transcript.md")
        if request.transcriptURL.standardizedFileURL != transcriptURL.standardizedFileURL {
            try? fileManager.removeItem(at: transcriptURL)
            try fileManager.moveItem(at: request.transcriptURL, to: transcriptURL)
        }

        let summaryURL = outputDir.appendingPathComponent("\(baseName)_summary.md")
        try Self.markdownSummary(for: summaryResult).write(
            to: summaryURL,
            atomically: true,
            encoding: .utf8
        )
        if let existingSummaryURL = request.existingSummaryURL,
           existingSummaryURL.standardizedFileURL != summaryURL.standardizedFileURL {
            try? fileManager.removeItem(at: existingSummaryURL)
        }

        diagnosticLog.info("要約やり直し完了 baseName=\(baseName)")
        return PipelineResult(
            meetingTitle: summaryResult.title,
            recordingURL: recordingDestURL,
            transcriptURL: transcriptURL,
            summaryURL: summaryURL
        )
    }

    private static func markdownSummary(for result: SummarizeResult) -> String {
        "# 要約\n\n## 会議名\n\(result.title)\n\n\(result.body)"
    }

    private static func strippingTranscriptHeading(_ markdown: String) -> String {
        guard markdown.hasPrefix(transcriptHeading) else { return markdown }
        return String(markdown.dropFirst(transcriptHeading.count))
    }

    /// 既存ファイル名の先頭が日時形式ならそれを引き継ぎ、崩れている場合だけ録画日時から作り直す。
    private static func baseNameDateString(
        recordingURL: URL,
        recordingDate: Date
    ) -> String {
        let baseName = recordingURL.deletingPathExtension().lastPathComponent
        let prefix = String(baseName.prefix(15))
        if prefix.count == 15, baseNameDateFormatter.date(from: prefix) != nil {
            return prefix
        }
        return baseNameDateFormatter.string(from: recordingDate)
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

    private static func availableBaseName(
        _ preferredBaseName: String,
        sourceURL: URL,
        outputDirectory: URL,
        extension ext: String,
        fileManager: FileManager
    ) -> String {
        var candidate = preferredBaseName
        var suffix = 2
        while true {
            let candidateURL = outputDirectory
                .appendingPathComponent(candidate)
                .appendingPathExtension(ext)
            if candidateURL.standardizedFileURL == sourceURL.standardizedFileURL
                || !fileManager.fileExists(atPath: candidateURL.path) {
                return candidate
            }
            candidate = "\(preferredBaseName)-\(suffix)"
            suffix += 1
        }
    }
}

private enum RecordingPipelineError: LocalizedError {
    case whisperModelNotSelected
    case summaryModelNotSelected
    case recordingNotFound(String)
    case transcriptNotFound(String)
    case transcriptEmpty(String)

    var errorDescription: String? {
        switch self {
        case .whisperModelNotSelected:
            "文字起こしモデルが選択されていません。設定からモデルをダウンロードしてください。"
        case .summaryModelNotSelected:
            "要約モデルが選択されていません。設定から要約モデルを選択してください。"
        case .recordingNotFound(let path):
            "処理を再開する録画ファイルが見つかりません: \(path)"
        case .transcriptNotFound(let path):
            "やり直しに使う文字起こしファイルが見つかりません: \(path)"
        case .transcriptEmpty(let path):
            "文字起こしファイルが空のため、要約をやり直せません: \(path)"
        }
    }
}
