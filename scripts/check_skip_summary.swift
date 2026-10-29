import Foundation

/// 要約を作らずに録画と文字起こしだけを保存し、あとから要約を作成すると
/// 日時部分を保ったまま会議名へ付け替わることを確認する。
/// `--no-ollama` を付けると、Ollama が要らない要約なしの保存だけを確認する。
@main
private enum SkipSummaryCheck {
    static func main() async {
        let arguments = CommandLine.arguments.dropFirst()
        let usesOllama = !arguments.contains("--no-ollama")
        let modelID = arguments.first { !$0.hasPrefix("--") } ?? "gemma4:12b"
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "MeetingScribe-skip-summary-check-\(UUID().uuidString)",
                isDirectory: true
            )
        let jobID = UUID()
        defer {
            try? fileManager.removeItem(at: root)
            if let workDirectory = try? PipelineWorkspace.workDirectory(for: jobID) {
                try? fileManager.removeItem(at: workDirectory)
            }
        }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let recordingURL = root.appendingPathComponent("recording_check.mp4")
            try Data("dummy recording".utf8).write(to: recordingURL)

            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = .current
            components.year = 2026
            components.month = 10
            components.day = 29
            components.hour = 10
            components.minute = 5
            let recordingDate = components.date!

            let pipeline = RecordingPipeline(
                transcription: FixedTranscriptionService(),
                summary: UnusedSummaryService()
            )
            print("Checking processRecording(skipsSummary: true)")
            let skipped = try await pipeline.processRecording(
                request: PipelineRequest(
                    id: jobID,
                    fileURL: recordingURL,
                    outputDirectoryURL: root,
                    recordingDate: recordingDate,
                    whisperModelID: "unused",
                    summaryModelID: "",
                    skipsSummary: true
                )
            ) { progress in
                if case .summarizing = progress {
                    fputs("FAIL: 要約なしのジョブが要約工程へ進みました\n", stderr)
                    exit(1)
                }
            }

            let expectedBaseName = "2026-10-29_1005_\(jobID.uuidString.prefix(8))"
            try require(
                skipped.recordingURL.lastPathComponent == "\(expectedBaseName).mp4",
                "録画のファイル名が想定と違います: \(skipped.recordingURL.lastPathComponent)"
            )
            try require(
                skipped.transcriptURL.lastPathComponent == "\(expectedBaseName)_transcript.md",
                "文字起こしのファイル名が想定と違います: \(skipped.transcriptURL.lastPathComponent)"
            )
            try require(skipped.summaryURL == nil, "要約なしなのに要約のURLが返りました")
            try require(
                skipped.meetingTitle == RecordingPipeline.untitledMeetingTitle,
                "要約なしの会議名が想定と違います: \(skipped.meetingTitle)"
            )
            try require(
                !fileManager.fileExists(atPath: recordingURL.path),
                "元の録画ファイルが残っています"
            )
            let afterSkip = try fileManager.contentsOfDirectory(atPath: root.path).sorted()
            try require(
                afterSkip == ["\(expectedBaseName).mp4", "\(expectedBaseName)_transcript.md"],
                "保存先に想定外のファイルがあります: \(afterSkip)"
            )
            print("PASS: 要約なしで保存 files=\(afterSkip)")
            guard usesOllama else { return }

            print("Checking resummarize from the skipped recording: model=\(modelID)")
            let summarizingPipeline = RecordingPipeline(
                transcription: FixedTranscriptionService(),
                summary: SummaryService()
            )
            let summarized = try await summarizingPipeline.resummarize(
                request: ResummarizeRequest(
                    id: UUID(),
                    recordingURL: skipped.recordingURL,
                    transcriptURL: skipped.transcriptURL,
                    existingSummaryURL: nil,
                    outputDirectoryURL: root,
                    recordingDate: recordingDate,
                    summaryModelID: modelID
                )
            ) { _ in }
            guard let summaryURL = summarized.summaryURL else {
                throw CheckError.failed("要約が作成されませんでした")
            }
            let newBaseName = summarized.recordingURL.deletingPathExtension().lastPathComponent
            try require(
                newBaseName.hasPrefix("2026-10-29_1005_") && newBaseName != expectedBaseName,
                "日時を保ったまま会議名へ付け替わっていません: \(newBaseName)"
            )
            let afterSummary = try fileManager.contentsOfDirectory(atPath: root.path).sorted()
            try require(
                afterSummary == [
                    "\(newBaseName).mp4",
                    "\(newBaseName)_summary.md",
                    "\(newBaseName)_transcript.md",
                ].sorted(),
                "要約作成後のファイルが想定と違います: \(afterSummary)"
            )
            let summaryText = try String(contentsOf: summaryURL, encoding: .utf8)
            try require(summaryText.count > 50, "要約本文が空です")
            print("PASS: 要約を作成 title=\(summarized.meetingTitle)")
            print("      files=\(afterSummary)")
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw CheckError.failed(message)
        }
    }

    private enum CheckError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                message
            }
        }
    }
}

private struct FixedTranscriptionService: TranscriptionServiceProtocol {
    func transcribe(
        audioOrVideoURL: URL,
        modelID: String,
        workingDirectory: URL?
    ) async throws -> String {
        """
        参加者A: 来週のリリースに向けて、残っている不具合を確認しました。
        参加者B: マイクの許可が出ない件は、署名のし直しで entitlements が消えていたことが原因でした。
        参加者C: 無音の録画で文字起こしが壊れる件は、無音検出を入れて直すことにしました。
        参加者A: 金曜日までに検証を終え、月曜日に配布することを決めました。
        """
    }
}

/// 要約なしの経路では要約を呼ばないため、呼ばれたら失敗させる
private struct UnusedSummaryService: SummaryServiceProtocol {
    func summarize(transcript: String, modelID: String) async throws -> SummarizeResult {
        throw CocoaError(.featureUnsupported)
    }

    func fetchAvailableModelIDs() async throws -> [String] {
        []
    }

    func pullModel(
        modelID: String,
        progressHandler: @Sendable @escaping (OllamaModelPullProgress) -> Void
    ) async throws {}
}
