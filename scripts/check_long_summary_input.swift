import Foundation

@main
struct LongSummaryInputCheck {
    static func main() async throws {
        let modelID = CommandLine.arguments.dropFirst().first ?? "gemma4:12b"
        let paragraph = """
        参加者A: 録画履歴の表示を次回リリースへ入れる方針を提案しました。
        参加者B: 賛成し、録画履歴の表示担当はB、期限は金曜日と確認しました。
        参加者C: データ移行方法は未決定で担当者も期限もないため、決定事項やアクションアイテムには含めないよう指摘しました。

        """
        let transcript = String(repeating: paragraph, count: 700)

        print(
            "Checking automatic summary splitting:",
            "model=\(modelID)",
            "utf8Bytes=\(transcript.utf8.count)"
        )
        let result = try await SummaryService().summarize(
            transcript: transcript,
            modelID: modelID
        )

        guard !result.title.isEmpty, !result.body.isEmpty else {
            throw CheckError.emptySummary
        }
        print("PASS: title=\(result.title)")
        print(result.body)
    }

    private enum CheckError: Error {
        case emptySummary
    }
}
