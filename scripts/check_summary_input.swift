import Foundation

@main
struct SummaryInputCheck {
    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else {
            throw CheckError.usage
        }

        let transcriptURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let modelID = CommandLine.arguments.dropFirst(2).first ?? "gemma4:12b"
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
        let result = try await SummaryService().summarize(
            transcript: transcript,
            modelID: modelID
        )

        guard !result.title.isEmpty, !result.body.isEmpty else {
            throw CheckError.emptySummary
        }
        print(result.title)
        print()
        print(result.body)
    }

    private enum CheckError: LocalizedError {
        case usage
        case emptySummary

        var errorDescription: String? {
            switch self {
            case .usage:
                return "使い方: check_summary_input <文字起こしファイル> [モデルID]"
            case .emptySummary:
                return "要約結果が空です。"
            }
        }
    }
}
