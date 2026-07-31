import Foundation

/// 要約が空のまま保存された録画を、保存済みの文字起こしから作り直せることを確認する。
@main
private enum ResummarizeCheck {
    static func main() async {
        let modelID = CommandLine.arguments.dropFirst().first ?? "gemma4:12b"
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "MeetingScribe-resummarize-check-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: root) }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

            // 会議名を決められずに保存された状態を再現する
            let originalBaseName = "2026-07-31_1432_無題"
            let recordingURL = root.appendingPathComponent("\(originalBaseName).mp4")
            let transcriptURL = root
                .appendingPathComponent("\(originalBaseName)_transcript.md")
            let summaryURL = root
                .appendingPathComponent("\(originalBaseName)_summary.md")

            try Data("dummy recording".utf8).write(to: recordingURL)
            try """
            # 文字起こし

            参加者A: 録画履歴をどの画面に表示するか、この会議で相談を始めました。
            参加者B: メニューバー内に置く案は項目が増えすぎるかもしれないと話しました。
            参加者C: 別ウィンドウにする案もあるが、まだ比較材料が足りないと話しました。
            参加者A: この場では結論を出さず、次回までに各案の画面イメージを持ち寄ることを確認しました。
            """.write(to: transcriptURL, atomically: true, encoding: .utf8)
            // 要約本文が空のまま保存されたファイル
            try "# 要約\n\n## 会議名\n無題\n\n"
                .write(to: summaryURL, atomically: true, encoding: .utf8)

            let pipeline = RecordingPipeline(
                transcription: UnusedTranscriptionService(),
                summary: SummaryService()
            )
            let request = ResummarizeRequest(
                id: UUID(),
                recordingURL: recordingURL,
                transcriptURL: transcriptURL,
                existingSummaryURL: summaryURL,
                outputDirectoryURL: root,
                recordingDate: Date(),
                summaryModelID: modelID
            )

            print("Checking resummarize: model=\(modelID) baseName=\(originalBaseName)")
            let result = try await pipeline.resummarize(request: request) { _ in }

            guard result.meetingTitle != "無題", !result.meetingTitle.isEmpty else {
                throw CheckError.titleNotUpdated(result.meetingTitle)
            }

            // 日時部分は既存ファイル名から引き継ぎ、会議名だけが変わる
            let newBaseName = result.recordingURL
                .deletingPathExtension()
                .lastPathComponent
            guard newBaseName.hasPrefix("2026-07-31_1432_") else {
                throw CheckError.datePrefixLost(newBaseName)
            }
            guard newBaseName != originalBaseName else {
                throw CheckError.baseNameNotRenamed(newBaseName)
            }

            for url in [result.recordingURL, result.transcriptURL, result.summaryURL] {
                guard fileManager.fileExists(atPath: url.path) else {
                    throw CheckError.missingOutput(url.lastPathComponent)
                }
            }
            for url in [recordingURL, transcriptURL, summaryURL] {
                guard !fileManager.fileExists(atPath: url.path) else {
                    throw CheckError.staleFileLeft(url.lastPathComponent)
                }
            }

            let summaryText = try String(
                contentsOf: result.summaryURL,
                encoding: .utf8
            )
            let body = summaryText.replacingOccurrences(
                of: "# 要約\n\n## 会議名\n\(result.meetingTitle)\n\n",
                with: ""
            )
            guard body.trimmingCharacters(in: .whitespacesAndNewlines).count > 50 else {
                throw CheckError.emptySummaryBody
            }

            let transcriptText = try String(
                contentsOf: result.transcriptURL,
                encoding: .utf8
            )
            guard transcriptText.contains("録画履歴をどの画面に表示するか") else {
                throw CheckError.transcriptNotPreserved
            }

            print("PASS: title=\(result.meetingTitle)")
            print("      baseName=\(newBaseName)")
        } catch {
            FileHandle.standardError.write(
                Data("FAIL: \(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }
    }

    private enum CheckError: LocalizedError {
        case titleNotUpdated(String)
        case datePrefixLost(String)
        case baseNameNotRenamed(String)
        case missingOutput(String)
        case staleFileLeft(String)
        case emptySummaryBody
        case transcriptNotPreserved

        var errorDescription: String? {
            switch self {
            case .titleNotUpdated(let title):
                "会議名が更新されませんでした: \(title)"
            case .datePrefixLost(let baseName):
                "既存ファイル名の日時部分が失われました: \(baseName)"
            case .baseNameNotRenamed(let baseName):
                "ファイル名が付け替えられていません: \(baseName)"
            case .missingOutput(let name):
                "やり直し後のファイルが見つかりません: \(name)"
            case .staleFileLeft(let name):
                "やり直し前のファイルが残っています: \(name)"
            case .emptySummaryBody:
                "要約本文が空のままです。"
            case .transcriptNotPreserved:
                "文字起こしの内容が保たれていません。"
            }
        }
    }
}

/// resummarize は文字起こしを実行しないため、呼ばれたら失敗させる
private struct UnusedTranscriptionService: TranscriptionServiceProtocol {
    func transcribe(
        audioOrVideoURL: URL,
        modelID: String,
        workingDirectory: URL?
    ) async throws -> String {
        throw CocoaError(.featureUnsupported)
    }
}
