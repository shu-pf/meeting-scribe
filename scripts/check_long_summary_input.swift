import Foundation

@main
struct LongSummaryInputCheck {
    static func main() async throws {
        let modelID = CommandLine.arguments.dropFirst().first ?? "gemma4:12b"
        let paragraph = """
        参加者A: 録画履歴をどの画面に表示するか、この会議で相談を始めました。
        参加者B: メニューバー内に置く案は項目が増えすぎるかもしれないと話しました。
        参加者C: 別ウィンドウにする案もあるが、まだ比較材料が足りないと話しました。
        参加者A: この場では結論を出さず、追加の作業、担当者、次回の相談予定も決めないことを確認しました。

        """
        let transcript = String(repeating: paragraph, count: 300)

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
        let forbiddenHeadings = [
            "決定事項", "ネクストアクション", "アクションアイテム"
        ]
        if forbiddenHeadings.contains(where: result.body.contains) {
            throw CheckError.forcedCategory(result.body)
        }
        let fabricatedActions = [
            "意見を集約", "検討を継続", "後日の相談", "別途相談"
        ]
        if fabricatedActions.contains(where: result.body.contains) {
            throw CheckError.fabricatedAction(result.body)
        }
        print("PASS: title=\(result.title)")
        print(result.body)
    }

    private enum CheckError: Error {
        case emptySummary
        case forcedCategory(String)
        case fabricatedAction(String)
    }
}
