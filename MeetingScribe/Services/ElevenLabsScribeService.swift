//
//  ElevenLabsScribeService.swift
//  MeetingScribe
//
//  ElevenLabs Scribe v2 によるクラウド文字起こし。
//  API: POST https://api.elevenlabs.io/v1/speech-to-text (multipart/form-data, xi-api-key)
//

import Foundation
import Security
import os

private nonisolated func scribeLogger() -> Logger {
    Logger(subsystem: "MeetingScribe", category: "ElevenLabsScribe")
}

/// 文字起こしモデルの選択肢として Whisper モデル ID と並べて扱う ID。
nonisolated enum ElevenLabsScribe {
    static let modelID = "elevenlabs-scribe-v2"
    static let displayName = "ElevenLabs Scribe v2（クラウド）"

    static func isCloudModel(_ modelID: String) -> Bool {
        modelID == Self.modelID
    }
}

/// ElevenLabs の API キーを Keychain に保存する。
nonisolated enum ElevenLabsAPIKeyStore {
    private static let service = "com.shu-pf.MeetingScribe.elevenlabs"
    private static let account = "api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static var hasKey: Bool { load() != nil }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        delete()
        guard !trimmed.isEmpty else { return true }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

nonisolated struct ElevenLabsScribeService: Sendable {
    private static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

    private let apiKeyProvider: @Sendable () -> String?

    init(apiKeyProvider: @escaping @Sendable () -> String? = { ElevenLabsAPIKeyStore.load() }) {
        self.apiKeyProvider = apiKeyProvider
    }

    /// WAV を送って文字起こしする。話者分離の結果は話者ごとの段落にまとめる。
    func transcribe(wavURL: URL, workingDirectory: URL) async throws -> String {
        guard let apiKey = apiKeyProvider() else {
            throw TranscriptionError.cloudAPIKeyMissing
        }

        // 5時間の WAV は数百MBになるため、multipart 本文をメモリではなくファイルに組み立てて送る。
        let boundary = "MeetingScribe-\(UUID().uuidString)"
        let bodyURL = workingDirectory.appendingPathComponent(UUID().uuidString + ".multipart")
        try Self.writeMultipartBody(to: bodyURL, boundary: boundary, wavURL: wavURL)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60 * 60
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let bodySize = (try? FileManager.default.attributesOfItem(atPath: bodyURL.path)[.size] as? Int) ?? 0
        scribeLogger().info("Scribe v2 送信開始 bytes=\(bodySize)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: bodyURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TranscriptionError.cloudRequestFailed(statusCode: nil, message: error.localizedDescription)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        scribeLogger().info("Scribe v2 応答 status=\(statusCode) bytes=\(data.count)")
        guard statusCode == 200 else {
            throw TranscriptionError.cloudRequestFailed(
                statusCode: statusCode,
                message: Self.errorMessage(from: data)
            )
        }

        let decoded: ScribeResponse
        do {
            decoded = try JSONDecoder().decode(ScribeResponse.self, from: data)
        } catch {
            throw TranscriptionError.outputEncodingFailed
        }
        return Self.format(decoded)
    }

    private static func writeMultipartBody(to url: URL, boundary: String, wavURL: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw TranscriptionError.outputEncodingFailed
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        func field(_ name: String, _ value: String) -> Data {
            Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8)
        }
        try handle.write(contentsOf: field("model_id", "scribe_v2"))
        try handle.write(contentsOf: field("language_code", "ja"))
        try handle.write(contentsOf: field("diarize", "true"))
        try handle.write(contentsOf: field("tag_audio_events", "false"))
        try handle.write(contentsOf: Data(
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8
        ))

        let input = try FileHandle(forReadingFrom: wavURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 8 * 1_024 * 1_024), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }
        try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }

    private static func errorMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? [String: Any],
               let message = detail["message"] as? String {
                return message
            }
            if let detail = object["detail"] as? String {
                return detail
            }
        }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : String(text.prefix(300))
    }

    /// 話者が変わるたびに段落を分け、「話者1: 」の見出しを付ける。話者が1人だけなら見出しを付けない。
    static func format(_ response: ScribeResponse) -> String {
        let words = response.words ?? []
        let speakers = Set(words.compactMap(\.speakerID))
        guard speakers.count > 1 else {
            return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var speakerNumbers: [String: Int] = [:]
        var paragraphs: [(speaker: String, text: String)] = []
        for word in words where word.type != "audio_event" {
            let speaker = word.speakerID ?? paragraphs.last?.speaker ?? ""
            if paragraphs.last?.speaker == speaker {
                paragraphs[paragraphs.count - 1].text += word.text
            } else {
                paragraphs.append((speaker, word.text))
            }
        }
        return paragraphs
            .compactMap { paragraph -> String? in
                let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let number = speakerNumbers[paragraph.speaker] ?? {
                    let next = speakerNumbers.count + 1
                    speakerNumbers[paragraph.speaker] = next
                    return next
                }()
                return "話者\(number): \(text)"
            }
            .joined(separator: "\n\n")
    }
}

nonisolated struct ScribeResponse: Decodable, Sendable {
    struct Word: Decodable, Sendable {
        let text: String
        let type: String?
        let speakerID: String?

        enum CodingKeys: String, CodingKey {
            case text
            case type
            case speakerID = "speaker_id"
        }
    }

    let text: String
    let words: [Word]?
}
