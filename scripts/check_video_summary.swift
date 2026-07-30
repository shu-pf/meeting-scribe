import Foundation

@main
struct VideoSummaryCheck {
    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else {
            throw CheckError.usage
        }

        let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let whisperModelID = CommandLine.arguments.dropFirst(2).first
            ?? "large-v3-turbo"
        let summaryModelID = CommandLine.arguments.dropFirst(3).first
            ?? "gemma4:12b"
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MeetingScribeVideoSummaryCheck-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        print("文字起こし中: \(videoURL.lastPathComponent)")
        let transcript = try await TranscriptionService().transcribe(
            audioOrVideoURL: videoURL,
            modelID: whisperModelID,
            workingDirectory: workingDirectory
        )
        guard !transcript.isEmpty else {
            throw CheckError.emptyTranscript
        }

        print("要約中: \(summaryModelID)")
        let result = try await SummaryService().summarize(
            transcript: transcript,
            modelID: summaryModelID
        )
        guard !result.title.isEmpty, !result.body.isEmpty else {
            throw CheckError.emptySummary
        }

        print()
        print(result.title)
        print()
        print(result.body)
    }

    private enum CheckError: LocalizedError {
        case usage
        case emptyTranscript
        case emptySummary

        var errorDescription: String? {
            switch self {
            case .usage:
                return """
                使い方: check_video_summary <動画> \
                [WhisperモデルID] [要約モデルID]
                """
            case .emptyTranscript:
                return "文字起こし結果が空です。"
            case .emptySummary:
                return "要約結果が空です。"
            }
        }
    }
}
