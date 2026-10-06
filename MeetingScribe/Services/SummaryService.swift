//
//  SummaryService.swift
//  MeetingScribe
//

import Foundation

/// 要約結果（会議タイトル + 要約本文）
struct SummarizeResult: Codable, Sendable {
    let title: String
    let body: String
}

struct OllamaModelPullProgress: Sendable {
    let status: String
    let fractionCompleted: Double?
}

protocol SummaryServiceProtocol: Sendable {
    func summarize(transcript: String, modelID: String) async throws -> SummarizeResult
    func fetchAvailableModelIDs() async throws -> [String]
    func pullModel(
        modelID: String,
        progressHandler: @Sendable @escaping (OllamaModelPullProgress) -> Void
    ) async throws
}

private let ollamaBaseURL = "http://localhost:11434"
private let tagsTimeout: TimeInterval = 5
/// 品質上限の5時間会議でも、ローカルLLMの初回ロードと生成を途中で打ち切らない。
private let generateTimeout: TimeInterval = 5 * 60 * 60
/// モデルが対応していても、ローカル実行時の負荷が過大にならない上限。
/// num_ctx はKVキャッシュを最大長で確保するため、131072では12B級モデルでも
/// 発熱でmacOSが緊急再起動した。分割要約のチャンクはこの長さに十分収まる。
private let maximumAutomaticContextLength = 32_768
/// 再起動直後はアプリがOllamaより先に起動するため、応答するまで待つ時間。
private let ollamaStartupTimeout: TimeInterval = 3 * 60
private let ollamaPollInterval: Duration = .seconds(3)
/// 生成中にOllamaが落ちた・再起動した場合に、同じ段階をやり直す回数。
private let generateConnectionRetryCount = 3
/// 発熱が深刻な間は次の生成を始めずに冷えるのを待つ。待ち続けて処理が止まらないよう上限を設ける。
private let thermalCooldownTimeout: TimeInterval = 20 * 60
private let thermalPollInterval: Duration = .seconds(30)
/// /api/show が利用できない場合も長文を安全に分割できる保守的な値。
private let fallbackContextLength = 8_192
/// 分割時の1チャンクが目標とする入力トークン数。
/// これより大きいとプロンプト処理の単価が二次的に悪化し、部分要約の圧縮率も上がりすぎて内容が失われる。
/// これより小さいと生成回数が増え、生成はプロンプト処理より一桁遅いため総処理時間が伸びる。
private let preferredChunkInputTokens = 15_360
/// 日本語の会議文字起こしをOllamaへ渡したときの実測換算（1トークンあたり約1.8バイト）。
/// 言語やモデルで前後するため、上限ではなく分割の目安としてのみ使う。
private let estimatedUTF8BytesPerToken = 1.8
/// 分割時の1チャンクの目安サイズ。コンテキスト長から決まる上限とあわせて小さい方を採用する。
private let preferredChunkUTF8Bytes = Int(
    Double(preferredChunkInputTokens) * estimatedUTF8BytesPerToken
)

/// 会議文字起こしを、モデルのコンテキスト長に収まる単位へ分割して要約する。
final class SummaryService: SummaryServiceProtocol {
    private let session: URLSession
    private let baseURL: URL
    private let diagnosticLog = DiagnosticLogger(category: "Summary")

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL ?? URL(string: ollamaBaseURL)!
        self.session = session
    }

    func summarize(transcript: String, modelID: String) async throws -> SummarizeResult {
        // 起動直後のOllamaへ問い合わせると、コンテキスト長も控えめな既定値へ落ちてしまうため先に待つ。
        try await waitUntilOllamaResponds()
        let modelContextLength =
            (try? await fetchModelContextLength(modelID: modelID))
            ?? fallbackContextLength
        let contextLength = min(
            max(modelContextLength, 2_048),
            maximumAutomaticContextLength
        )
        // 思考対応モデルは think=false でも数千トークンを使うことがあるため、上限を下げても出力枠は確保する。
        let finalOutputTokens = min(8_192, max(512, contextLength / 4))
        let partialOutputTokens = min(2_048, max(256, contextLength / 16))
        let promptTokenReserve = min(4_096, max(1_024, contextLength / 4))
        // 1回の生成へ渡せる入力の上限。統合段階でもこの上限を使う。
        let inputByteBudget = max(
            512,
            contextLength - finalOutputTokens - promptTokenReserve
        )
        // 分割時は上限まで詰めず、処理時間と要約の密度が両立する大きさに抑える。
        let chunkByteBudget = min(inputByteBudget, preferredChunkUTF8Bytes)

        let transcriptChunks = Self.chunk(
            transcript,
            maximumUTF8Bytes: chunkByteBudget
        )
        diagnosticLog.info(
            "要約入力を分割 chunkCount=\(transcriptChunks.count)"
                + " contextLength=\(contextLength) inputByteBudget=\(inputByteBudget)"
                + " chunkByteBudget=\(chunkByteBudget)"
        )
        if transcriptChunks.count == 1, let transcriptChunk = transcriptChunks.first {
            let raw = try await generate(
                prompt: Self.finalPrompt(for: transcriptChunk),
                modelID: modelID,
                contextLength: contextLength,
                outputTokens: finalOutputTokens,
                stage: "最終要約"
            )
            return Self.parseSummarizeResult(raw)
        }

        var partialSummaries: [String] = []
        partialSummaries.reserveCapacity(transcriptChunks.count)
        for (index, chunk) in transcriptChunks.enumerated() {
            try Task.checkCancellation()
            let raw = try await generate(
                prompt: Self.partialPrompt(
                    for: chunk,
                    index: index + 1,
                    total: transcriptChunks.count
                ),
                modelID: modelID,
                contextLength: contextLength,
                outputTokens: partialOutputTokens,
                stage: "部分要約\(index + 1)/\(transcriptChunks.count)"
            )
            partialSummaries.append(
                Self.prefix(
                    raw,
                    maximumUTF8Bytes: max(256, inputByteBudget / 2)
                )
            )
        }

        let consolidated = try await consolidate(
            partialSummaries,
            modelID: modelID,
            contextLength: contextLength,
            inputByteBudget: inputByteBudget,
            outputTokens: partialOutputTokens
        )
        let raw = try await generate(
            prompt: Self.finalPrompt(for: consolidated),
            modelID: modelID,
            contextLength: contextLength,
            outputTokens: finalOutputTokens,
            stage: "最終要約"
        )
        return Self.parseSummarizeResult(raw)
    }

    private func consolidate(
        _ summaries: [String],
        modelID: String,
        contextLength: Int,
        inputByteBudget: Int,
        outputTokens: Int
    ) async throws -> String {
        var current = summaries

        while true {
            try Task.checkCancellation()
            let combined = Self.numberedSections(current)
            if combined.utf8.count <= inputByteBudget {
                return combined
            }

            let groups = Self.chunk(
                combined,
                maximumUTF8Bytes: inputByteBudget
            )
            var next: [String] = []
            next.reserveCapacity(groups.count)
            for (index, group) in groups.enumerated() {
                let raw = try await generate(
                    prompt: Self.consolidationPrompt(
                        for: group,
                        index: index + 1,
                        total: groups.count
                    ),
                    modelID: modelID,
                    contextLength: contextLength,
                    outputTokens: outputTokens,
                    stage: "部分要約の統合\(index + 1)/\(groups.count)"
                )
                next.append(
                    Self.prefix(
                        raw,
                        maximumUTF8Bytes: max(256, inputByteBudget / 2)
                    )
                )
            }
            current = next
        }
    }

    /// Ollamaへの接続が切れても、Ollamaが応答するまで待って同じ段階をやり直す。
    private func generate(
        prompt: String,
        modelID: String,
        contextLength: Int,
        outputTokens: Int,
        stage: String
    ) async throws -> String {
        var attempt = 1
        while true {
            try await waitForThermalHeadroom(stage: stage)
            do {
                return try await generateOnce(
                    prompt: prompt,
                    modelID: modelID,
                    contextLength: contextLength,
                    outputTokens: outputTokens,
                    stage: stage
                )
            } catch let error as URLError where Self.isOllamaConnectionError(error)
                && attempt < generateConnectionRetryCount {
                diagnosticLog.warning(
                    "Ollamaへの接続が切れたため再試行します stage=\(stage)"
                        + " attempt=\(attempt) code=\(error.code.rawValue)"
                )
                attempt += 1
                try await waitUntilOllamaResponds()
            } catch let error as URLError where Self.isOllamaConnectionError(error) {
                throw SummaryError.ollamaUnreachable
            }
        }
    }

    /// `/api/tags` が応答するまで待つ。起動しないまま上限を過ぎたら接続できないエラーにする。
    private func waitUntilOllamaResponds() async throws {
        let deadline = Date().addingTimeInterval(ollamaStartupTimeout)
        var hasLoggedWaiting = false
        while true {
            do {
                _ = try await fetchAvailableModelIDs()
                if hasLoggedWaiting {
                    diagnosticLog.info("Ollamaの応答を確認しました")
                }
                return
            } catch let error as URLError
                where Self.isOllamaConnectionError(error) || error.code == .timedOut {
                guard Date() < deadline else {
                    diagnosticLog.error(
                        "Ollamaが応答しないため要約を中止します code=\(error.code.rawValue)"
                    )
                    throw SummaryError.ollamaUnreachable
                }
                if !hasLoggedWaiting {
                    diagnosticLog.info(
                        "Ollamaの起動を待っています code=\(error.code.rawValue)"
                    )
                    hasLoggedWaiting = true
                }
                try await Task.sleep(for: ollamaPollInterval)
            }
        }
    }

    /// 発熱が深刻な間は次の生成を始めない。上限を過ぎたら処理を止めないよう続行する。
    private func waitForThermalHeadroom(stage: String) async throws {
        let deadline = Date().addingTimeInterval(thermalCooldownTimeout)
        var hasLoggedWaiting = false
        while Self.isThermalStateSevere(ProcessInfo.processInfo.thermalState) {
            guard Date() < deadline else {
                diagnosticLog.warning(
                    "発熱が続いていますが待機上限に達したため生成を続けます stage=\(stage)"
                )
                return
            }
            if !hasLoggedWaiting {
                diagnosticLog.warning(
                    "発熱が深刻なため生成を待機します stage=\(stage)"
                        + " thermalState=\(ProcessInfo.processInfo.thermalState.rawValue)"
                )
                hasLoggedWaiting = true
            }
            try await Task.sleep(for: thermalPollInterval)
        }
        if hasLoggedWaiting {
            diagnosticLog.info("発熱が収まったため生成を再開します stage=\(stage)")
        }
    }

    private static func isThermalStateSevere(_ state: ProcessInfo.ThermalState) -> Bool {
        switch state {
        case .serious, .critical:
            true
        case .nominal, .fair:
            false
        @unknown default:
            false
        }
    }

    /// Ollamaが未起動・再起動中・異常終了したときの接続エラー。生成のタイムアウトは含めない。
    private static func isOllamaConnectionError(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost,
             .notConnectedToInternet:
            true
        default:
            false
        }
    }

    private func generateOnce(
        prompt: String,
        modelID: String,
        contextLength: Int,
        outputTokens: Int,
        stage: String
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = generateTimeout
        let body: [String: Any] = [
            "model": modelID,
            "prompt": prompt,
            "stream": false,
            // 思考対応モデルは既定で思考を生成するが、その分は応答に含まれず num_predict だけを
            // 消費する。長文要約では思考が上限に達して本文が空になるため、思考を無効化する。
            "think": false,
            "options": [
                "num_ctx": contextLength,
                "num_predict": outputTokens,
                "temperature": 0
            ] as [String: Any]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SummaryError.invalidResponse
        }

        if http.statusCode != 200 {
            throw SummaryError.apiError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let text = decoded.response ?? ""
        diagnosticLog.info(
            "生成応答 stage=\(stage) characterCount=\(text.count)"
                + " doneReason=\(decoded.doneReason ?? "-")"
                + " promptEvalCount=\(decoded.promptEvalCount ?? -1)"
                + " evalCount=\(decoded.evalCount ?? -1)"
        )
        if decoded.doneReason == "length" {
            diagnosticLog.warning(
                "生成が出力上限で打ち切られました stage=\(stage) outputTokens=\(outputTokens)"
            )
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            diagnosticLog.error(
                "生成応答が空でした stage=\(stage) doneReason=\(decoded.doneReason ?? "-")"
                    + " evalCount=\(decoded.evalCount ?? -1)"
            )
            throw SummaryError.emptyGeneration(stage: stage)
        }
        return text
    }

    private func fetchModelContextLength(modelID: String) async throws -> Int {
        let url = baseURL.appendingPathComponent("api/show")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = tagsTimeout
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["model": modelID]
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SummaryError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw SummaryError.apiError(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }
        guard let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let modelInfo = root["model_info"] as? [String: Any],
              let contextLength = modelInfo.first(where: {
                  $0.key.hasSuffix(".context_length")
              })?.value as? NSNumber else {
            throw SummaryError.invalidResponse
        }
        return contextLength.intValue
    }

    private static func partialPrompt(
        for transcript: String,
        index: Int,
        total: Int
    ) -> String {
        """
        以下は会議文字起こしの全\(total)部分中\(index)番目です。
        後で全体をまとめられるよう、実際に話された内容を具体性を保って日本語で要約してください。
        質問と回答、合意、未確定の内容を、発言の確度のまま残してください。
        推測はしないでください。
        タイトルは不要です。

        --- 文字起こし部分 ---
        \(transcript)
        """
    }

    private static func consolidationPrompt(
        for summaries: String,
        index: Int,
        total: Int
    ) -> String {
        """
        以下は長い会議文字起こしから作った部分要約の全\(total)グループ中\(index)番目です。
        重複をまとめながら、実際に話された内容を具体性を保って日本語で要約してください。
        質問と回答、合意、未確定の内容を、発言の確度のまま残してください。
        推測はしないでください。
        タイトルは不要です。

        --- 部分要約 ---
        \(summaries)
        """
    }

    private static func finalPrompt(for source: String) -> String {
        """
        以下の会議内容を、後から内容を理解できる詳しさで日本語要約してください。
        1行目に簡潔なタイトルを書き、空行を挟んでください。
        本文は最初に会議全体の概要を書き、続けて話題ごとの番号付き見出しと文章で整理してください。
        「決定事項」「今後の対応」などの定型項目は作らず、実際の話題を見出しにしてください。
        会議全体を最後まで確認し、固有名詞や数値を含め、実際に話された内容だけを使ってください。
        提案、質問、未確定の内容はそのまま書き、推測や補完をしないでください。
        短さより網羅性を優先し、発言された手順、理由、具体例、未解決事項を残してください。

        --- 会議内容 ---
        \(source)
        """
    }

    private static func numberedSections(_ sections: [String]) -> String {
        sections.enumerated().map { index, section in
            "## 部分\(index + 1)\n\(section)"
        }.joined(separator: "\n\n")
    }

    /// トークン数はUTF-8バイト数を超えないため、未知のtokenizerでも上限を越えない。
    private static func chunk(
        _ text: String,
        maximumUTF8Bytes: Int
    ) -> [String] {
        guard text.utf8.count > maximumUTF8Bytes else {
            return [text]
        }

        var chunks: [String] = []
        var current = ""
        var currentBytes = 0

        func flushCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
            current = ""
            currentBytes = 0
        }

        for paragraph in text.components(separatedBy: "\n") {
            let paragraphWithBreak = paragraph + "\n"
            let paragraphBytes = paragraphWithBreak.utf8.count
            if paragraphBytes <= maximumUTF8Bytes {
                if currentBytes + paragraphBytes > maximumUTF8Bytes {
                    flushCurrent()
                }
                current += paragraphWithBreak
                currentBytes += paragraphBytes
                continue
            }

            flushCurrent()
            for character in paragraphWithBreak {
                let characterBytes = String(character).utf8.count
                if currentBytes + characterBytes > maximumUTF8Bytes {
                    flushCurrent()
                }
                current.append(character)
                currentBytes += characterBytes
            }
        }
        flushCurrent()
        return chunks
    }

    private static func prefix(
        _ text: String,
        maximumUTF8Bytes: Int
    ) -> String {
        guard text.utf8.count > maximumUTF8Bytes else {
            return text
        }
        var result = ""
        var byteCount = 0
        for character in text {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= maximumUTF8Bytes else {
                break
            }
            result.append(character)
            byteCount += characterBytes
        }
        return result
    }

    /// LLM の応答を「1行目=タイトル、2行目以降=本文」でパースする
    private static func parseSummarizeResult(_ raw: String) -> SummarizeResult {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let title: String
        let body: String
        if lines.isEmpty {
            title = "無題"
            body = ""
        } else {
            let first = lines[0].trimmingCharacters(in: .whitespaces)
            title = first.isEmpty ? "無題" : first
            body = lines.count > 1 ? lines[1...].joined(separator: "\n").trimmingCharacters(in: .whitespaces) : ""
        }
        return SummarizeResult(title: title, body: body)
    }

    func fetchAvailableModelIDs() async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = tagsTimeout

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SummaryError.invalidResponse
        }

        if http.statusCode != 200 {
            throw SummaryError.apiError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models?.map(\.name) ?? []
    }

    func pullModel(
        modelID: String,
        progressHandler: @Sendable @escaping (OllamaModelPullProgress) -> Void
    ) async throws {
        let url = baseURL.appendingPathComponent("api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = generateTimeout
        request.httpBody = try JSONEncoder().encode(
            OllamaPullRequest(model: modelID, stream: true)
        )

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SummaryError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 412 {
                throw SummaryError.ollamaUpdateRequired
            }
            throw SummaryError.apiError(statusCode: http.statusCode, body: nil)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty else { continue }
            let update = try JSONDecoder().decode(
                OllamaPullResponse.self,
                from: Data(line.utf8)
            )
            if let error = update.error, !error.isEmpty {
                if error.localizedCaseInsensitiveContains(
                    "requires a newer version of Ollama"
                ) {
                    throw SummaryError.ollamaUpdateRequired
                }
                throw SummaryError.modelPullFailed(error)
            }
            let fraction: Double?
            if let total = update.total, total > 0, let completed = update.completed {
                fraction = min(max(Double(completed) / Double(total), 0), 1)
            } else if update.status == "success" {
                fraction = 1
            } else {
                fraction = nil
            }
            progressHandler(
                OllamaModelPullProgress(
                    status: update.status ?? "モデルを準備中…",
                    fractionCompleted: fraction
                )
            )
        }
    }
}

// MARK: - API Response Types

private struct OllamaGenerateResponse: Decodable {
    let response: String?
    let doneReason: String?
    let promptEvalCount: Int?
    let evalCount: Int?

    private enum CodingKeys: String, CodingKey {
        case response
        case doneReason = "done_reason"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModelTag]?
}

private struct OllamaModelTag: Decodable {
    let name: String
}

private struct OllamaPullRequest: Encodable {
    let model: String
    let stream: Bool
}

private struct OllamaPullResponse: Decodable {
    let status: String?
    let total: Int64?
    let completed: Int64?
    let error: String?
}

// MARK: - Errors

enum SummaryError: Error, LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, body: String?)
    case ollamaUpdateRequired
    case modelPullFailed(String)
    case emptyGeneration(stage: String)
    case ollamaUnreachable

    var errorDescription: String? {
        switch self {
        case .ollamaUnreachable:
            return "Ollama に接続できませんでした。Ollama が起動していることを確認してから、再実行してください。"
        case .invalidResponse:
            return "Ollama からの応答が不正です。"
        case .emptyGeneration(let stage):
            return "要約モデルが空の応答を返しました（\(stage)）。別の要約モデルを選択するか、Ollama とモデルを更新してからやり直してください。"
        case .apiError(let code, let body):
            if code == 404 || code == 503 {
                return "Ollama が起動していないか、モデルが見つかりません。Ollama を起動し、要約用モデルをインストールしてください。"
            }
            return "Ollama API エラー（\(code)）: \(body ?? "")"
        case .ollamaUpdateRequired:
            return "このモデルのダウンロードには、より新しいOllamaが必要です。Ollamaを最新版へ更新してから、もう一度ダウンロードしてください。"
        case .modelPullFailed(let message):
            return "Ollamaモデルのダウンロードに失敗しました: \(message)"
        }
    }
}
