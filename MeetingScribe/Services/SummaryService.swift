//
//  SummaryService.swift
//  MeetingScribe
//

import Foundation

/// 要約結果（会議タイトル + 要約本文）
struct SummarizeResult: Sendable {
    let title: String
    let body: String
}

protocol SummaryServiceProtocol: Sendable {
    func summarize(transcript: String, modelID: String, numCtx: Int?) async throws -> SummarizeResult
    func fetchAvailableModelIDs() async throws -> [String]
}

private let ollamaBaseURL = "http://localhost:11434"
private let tagsTimeout: TimeInterval = 5
/// 1時間超の会議も見込んだコンテキスト長（128K トークン）
private let defaultNumCtx = 131_072
/// 要約文が途中で切れないよう生成トークン上限を指定
private let defaultNumPredict = 8_192

/// 会議文字起こしを Ollama の /api/generate で要約する。
final class SummaryService: SummaryServiceProtocol {
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL ?? URL(string: ollamaBaseURL)!
        self.session = session
    }

    func summarize(transcript: String, modelID: String, numCtx: Int? = nil) async throws -> SummarizeResult {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
            以下の会議の文字起こしを要約してください。
            出力形式は必ず次のようにしてください：
            1行目: 会議タイトルだけを1行で書く。
            2行目: 空行。
            3行目以降: 要約本文（議題・決定事項・アクションアイテムに整理して書く）。
            """
        let prompt = systemPrompt + "\n\n" + transcript

        let ctx = numCtx ?? defaultNumCtx
        let body: [String: Any] = [
            "model": modelID,
            "prompt": prompt,
            "stream": false,
            "options": [
                "num_ctx": ctx,
                "num_predict": defaultNumPredict
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
        let raw = decoded.response ?? ""
        return Self.parseSummarizeResult(raw)
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

// MARK: - Errors

enum SummaryError: Error, LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ollama からの応答が不正です。"
        case .apiError(let code, let body):
            if code == 404 || code == 503 {
                return "Ollama が起動していないか、モデルが見つかりません。Ollama を起動し、要約用モデルをインストールしてください。"
            }
            return "Ollama API エラー（\(code)）: \(body ?? "")"
        }
    }
}
