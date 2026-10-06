import Foundation

/// 再起動直後にOllamaがまだ起動していない場合と、生成中に接続が切れた場合に、
/// 要約が失敗せずOllamaの応答を待って完了することを確認する。
///
/// 使い方: 疑似Ollamaを起動するスクリプトと組み合わせる。
///   python3 scripts/fake_ollama.py <port> <起動までの秒数> <生成で切断する回数> &
///   swiftc -parse-as-library scripts/check_ollama_reconnect.swift \
///     MeetingScribe/Services/SummaryService.swift MeetingScribe/Services/DiagnosticLogger.swift \
///     -o /tmp/check_ollama_reconnect && /tmp/check_ollama_reconnect <port>
@main
struct OllamaReconnectCheck {
    static func main() async throws {
        let port = CommandLine.arguments.dropFirst().first ?? "11999"
        let service = SummaryService(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        let startedAt = Date()
        let result = try await service.summarize(
            transcript: "参加者A: 次回の定例は木曜に行うと話しました。",
            modelID: "fake-model"
        )
        guard !result.title.isEmpty, !result.body.isEmpty else {
            throw CheckError.emptySummary
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        print("PASS: title=\(result.title) elapsed=\(Int(elapsed))s")
    }

    private enum CheckError: Error {
        case emptySummary
    }
}
