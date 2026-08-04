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
        // macOSのファイルシステム表現に依存せず、保存時の名前は常にNFCへ揃える。
        // 旧バージョンが作ったチェックポイントから再開する場合もここで正規化する。
        let baseName = summaryCheckpoint.baseName.precomposedStringWithCanonicalMapping

        // 5. 録画を完成名へ移動（同じ出力フォルダ内なので再コピーしない）
        let recordingDestURL = Self.nfcFileURL(
            fileName: "\(baseName).\(ext)",
            in: outputDir
        )
        let samePath = fileURL.standardizedFileURL.path == recordingDestURL.standardizedFileURL.path
        if !samePath {
            if fileManager.fileExists(atPath: fileURL.path) {
                try Self.moveItemNFC(at: fileURL, to: recordingDestURL)
            } else if !fileManager.fileExists(atPath: recordingDestURL.path) {
                throw RecordingPipelineError.recordingNotFound(fileURL.path)
            }
        }
        Self.renameToNFCIfNeeded(at: recordingDestURL)

        // 6. チェックポイントから文字起こしを完成名で保存する
        let transcriptURL = Self.nfcFileURL(
            fileName: "\(baseName)_transcript.md",
            in: outputDir
        )
        try Self.writeNFC(markdownTranscript, to: transcriptURL)

        // 7. 要約を出力（先頭に会議名を明示）
        let summaryURL = Self.nfcFileURL(
            fileName: "\(baseName)_summary.md",
            in: outputDir
        )
        try Self.writeNFC(Self.markdownSummary(for: summaryResult), to: summaryURL)
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
        // 中断前のチェックポイントにNFDの名前が残っていてもNFCで保存する。
        let baseName = summaryCheckpoint.baseName.precomposedStringWithCanonicalMapping
        diagnosticLog.info("要約完了")

        await onProgress(.saving)

        // 録画を新しい会議名へ付け替える。録画が失われていても要約は残す。
        var recordingDestURL = Self.nfcFileURL(
            fileName: "\(baseName).\(ext)",
            in: outputDir
        )
        if request.recordingURL.standardizedFileURL != recordingDestURL.standardizedFileURL {
            if fileManager.fileExists(atPath: request.recordingURL.path) {
                try Self.moveItemNFC(at: request.recordingURL, to: recordingDestURL)
            } else if !fileManager.fileExists(atPath: recordingDestURL.path) {
                diagnosticLog.warning(
                    "やり直し対象の録画が見つからないため名前を変更しません path=\(request.recordingURL.path)"
                )
                recordingDestURL = request.recordingURL
            }
        }
        Self.renameToNFCIfNeeded(at: recordingDestURL)

        // 文字起こしも同じ会議名へ揃える。
        let transcriptURL = Self.nfcFileURL(
            fileName: "\(baseName)_transcript.md",
            in: outputDir
        )
        if request.transcriptURL.standardizedFileURL != transcriptURL.standardizedFileURL {
            try Self.moveItemNFC(at: request.transcriptURL, to: transcriptURL)
        }
        Self.renameToNFCIfNeeded(at: transcriptURL)

        let summaryURL = Self.nfcFileURL(
            fileName: "\(baseName)_summary.md",
            in: outputDir
        )
        try Self.writeNFC(Self.markdownSummary(for: summaryResult), to: summaryURL)
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
        let trimmed = title
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }
        let joined = components.joined()
        let collapsed = joined.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        let result = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if result.isEmpty { return "無題" }
        return String(result.prefix(80)).precomposedStringWithCanonicalMapping
    }

    /// `URL.appendingPathComponent` はmacOSでファイル名をNFDへ変換するため、
    /// NFCのUTF-8表現を保持したfile URLを直接組み立てる。
    private static func nfcFileURL(fileName: String, in directory: URL) -> URL {
        let normalizedFileName = fileName.precomposedStringWithCanonicalMapping
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encodedFileName = normalizedFileName.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? normalizedFileName
        let directoryString = directory.absoluteString.hasSuffix("/")
            ? directory.absoluteString
            : directory.absoluteString + "/"
        return URL(string: directoryString + encodedFileName)!
    }

    /// FoundationのファイルAPIはパスをNFDへ分解してからファイルシステムへ渡すため、
    /// 保存名をNFCで確定させる操作はrename(2)へUTF-8バイト列を直接渡して行う。
    /// 移動先に既存ファイルがあれば置き換える。
    private static func moveItemNFC(at source: URL, to destination: URL) throws {
        do {
            try posixRename(fromPath: source.path, toPath: destination.path)
        } catch let error as NSError
            where error.domain == NSPOSIXErrorDomain && error.code == Int(EXDEV) {
            // ボリュームをまたぐ移動はrename(2)が使えないためFoundationで移動し、名前だけ付け替える
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: source, to: destination)
            renameToNFCIfNeeded(at: destination)
        }
    }

    /// Foundationの書き込みは保存名をNFDへ分解するため、
    /// 同じフォルダ内の一時名で書いてからNFC名へrename(2)で付け替える。
    private static func writeNFC(_ content: String, to destination: URL) throws {
        let tempURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        do {
            try posixRename(fromPath: tempURL.path, toPath: destination.path)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    private static func posixRename(fromPath: String, toPath: String) throws {
        var fromInfo = stat()
        var toInfo = stat()
        if stat(fromPath, &fromInfo) == 0, stat(toPath, &toInfo) == 0,
           fromInfo.st_dev != toInfo.st_dev || fromInfo.st_ino != toInfo.st_ino {
            // 既存エントリを置き換えるrenameはAPFSが元の名前バイト列を保持するため、先に削除する
            unlink(toPath)
        }
        guard rename(fromPath, toPath) == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: toPath]
            )
        }
    }

    /// ディスク上の実名が旧バージョンの残したNFDの場合にNFCへ付け替える。
    /// 正規化だけが異なる同一ファイルへのrename(2)は名前バイト列を更新する。
    /// 失敗しても実害はないため黙って何もしない。
    private static func renameToNFCIfNeeded(at url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(fd, F_GETPATH, &pathBuffer) == 0 else { return }
        let storedPath = String(cString: pathBuffer)
        let storedName = (storedPath as NSString).lastPathComponent
        let nfcName = storedName.precomposedStringWithCanonicalMapping
        // Stringの==は正準等価で比較しNFDとNFCを同一視するため、UTF-8バイト列で比較する
        guard Array(storedName.utf8) != Array(nfcName.utf8) else { return }
        let directoryPath = (storedPath as NSString).deletingLastPathComponent
        rename(storedPath, directoryPath + "/" + nfcName)
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
            let candidateURL = nfcFileURL(
                fileName: "\(candidate).\(ext)",
                in: outputDirectory
            )
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
