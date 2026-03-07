//
//  SummaryService.swift
//  MeetingScribe
//

import Foundation

protocol SummaryServiceProtocol: Sendable {
    func summarize(transcript: String, modelID: String) async throws -> String
    func fetchAvailableModelIDs() async throws -> [String]
}

private let ollamaBaseURL = "http://localhost:11434"
private let generateTimeout: TimeInterval = 60
private let tagsTimeout: TimeInterval = 5

/// 会議文字起こしを Ollama の /api/generate で要約する。
final class SummaryService: SummaryServiceProtocol {
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL ?? URL(string: ollamaBaseURL)!
        self.session = session
    }

    func summarize(transcript: String, modelID: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = generateTimeout

        let systemPrompt = "以下の会議の文字起こしを要約し、議題・決定事項・アクションアイテムに整理して出力してください。"
        let prompt = systemPrompt + "\n\n" + transcript

        let body: [String: Any] = [
            "model": modelID,
            "prompt": prompt,
            "stream": false
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
