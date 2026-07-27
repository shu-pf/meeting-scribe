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
/// モデルが対応していても、ローカル実行時のメモリ使用量が過大にならない上限。
private let maximumAutomaticContextLength = 131_072
/// /api/show が利用できない場合も長文を安全に分割できる保守的な値。
private let fallbackContextLength = 8_192

/// 会議文字起こしを、モデルのコンテキスト長に収まる単位へ分割して要約する。
final class SummaryService: SummaryServiceProtocol {
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL ?? URL(string: ollamaBaseURL)!
        self.session = session
    }

    func summarize(transcript: String, modelID: String) async throws -> SummarizeResult {
        let modelContextLength =
            (try? await fetchModelContextLength(modelID: modelID))
            ?? fallbackContextLength
        let contextLength = min(
            max(modelContextLength, 2_048),
            maximumAutomaticContextLength
        )
        let finalOutputTokens = min(8_192, max(512, contextLength / 8))
        let partialOutputTokens = min(2_048, max(256, contextLength / 16))
        let promptTokenReserve = min(4_096, max(1_024, contextLength / 4))
        let inputByteBudget = max(
            512,
            contextLength - finalOutputTokens - promptTokenReserve
        )

        let transcriptChunks = Self.chunk(
            transcript,
            maximumUTF8Bytes: inputByteBudget
        )
        if transcriptChunks.count == 1, let transcriptChunk = transcriptChunks.first {
            let raw = try await generate(
                prompt: Self.finalPrompt(for: transcriptChunk),
                modelID: modelID,
                contextLength: contextLength,
                outputTokens: finalOutputTokens
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
                outputTokens: partialOutputTokens
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
            outputTokens: finalOutputTokens
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
                    outputTokens: outputTokens
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

    private func generate(
        prompt: String,
        modelID: String,
        contextLength: Int,
        outputTokens: Int
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
        return decoded.response ?? ""
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
        後で全体を統合できるよう、この部分に明示された重要情報を日本語で整理してください。
        議題、意見、決定事項、未決事項、担当者と期限を含むアクションアイテムを、
        発言の意味を変えず簡潔に残してください。タイトルは不要です。
        推測や補完をせず、存在しない決定・担当・期限を作らないでください。
        担当者や期限は、それが明示された対象との対応関係を崩さないでください。
        未決事項をアクションアイテムに変換しないでください。

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
        重複をまとめながら、後で会議全体を統合するための日本語の要点へ圧縮してください。
        決定事項、未決事項、担当者、期限、重要な根拠を失わないでください。
        タイトルは不要です。推測や補完は一切行わないでください。
        担当者や期限を別の議題へ付け替えず、未決事項をアクションアイテムに変換しないでください。

        --- 部分要約 ---
        \(summaries)
        """
    }

    private static func finalPrompt(for source: String) -> String {
        """
        以下の会議内容を要約してください。
        出力は必ず日本語で、次の形式にしてください。
        1行目: 会議タイトルだけを1行で書く。
        2行目: 空行。
        3行目以降: 要約本文を議題・決定事項・アクションアイテムに整理して書く。

        重要なルール：
        - 明示的に含まれている事実のみを書いてください。
        - 実際に決定されていない事項を「決定事項」に含めないでください。
        - 言及されていない担当者、期限、アクションアイテムを捏造しないでください。
        - 担当者や期限は、それが明示された対象との対応関係を維持してください。
        - 未決事項をアクションアイテムに変換しないでください。
        - 該当する内容がないセクションは省略してください。
        - 推測や補完は一切行わないでください。

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

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ollama からの応答が不正です。"
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
