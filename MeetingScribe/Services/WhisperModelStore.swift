//
//  WhisperModelStore.swift
//  MeetingScribe
//

import Foundation

/// ダウンロード可能な Whisper モデル一覧と保存先を定義し、ダウンロード済み一覧を提供する。
protocol WhisperModelStoreProtocol: Sendable {
    /// ダウンロード可能なモデル ID 一覧（tiny, base, small, medium, large-v3, large-v3-turbo 等）
    var downloadableModelIDs: [String] { get }
    /// Application Support 配下の Whisper モデル用ディレクトリ URL
    func modelsDirectoryURL() throws -> URL
    /// 指定ディレクトリ内に存在するダウンロード済みモデル ID 一覧（ファイル名 ggml-<id>.bin から取得）
    func downloadedModelIDs() async -> [String]
    /// 指定モデルのダウンロード URL（Hugging Face）
    func downloadURL(forModelID modelID: String) -> URL?
    /// 指定モデルのローカルファイル URL（modelsDirectoryURL()/ggml-<id>.bin）
    func localFileURL(forModelID modelID: String) async -> URL?
}

final class WhisperModelStore: WhisperModelStoreProtocol {
    static let shared = WhisperModelStore()

    /// 対応するモデル ID。whisper.cpp の download-ggml-model.sh と整合させる。
    let downloadableModelIDs: [String] = [
        "tiny",
        "base",
        "small",
        "medium",
        "large-v3",
        "large-v3-turbo",
    ]

    private let fileManager = FileManager.default
    private let baseURL: URL? = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MeetingScribe/WhisperModels", isDirectory: true)
    }()

    private static let urlBase = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml"

    func modelsDirectoryURL() throws -> URL {
        guard let url = baseURL else {
            throw WhisperModelStoreError.applicationSupportUnavailable
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func downloadedModelIDs() async -> [String] {
        guard let dir = baseURL else { return [] }
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents
            .filter { $0.pathExtension == "bin" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { last in last.hasPrefix("ggml-") }
            .map { $0.replacingOccurrences(of: "ggml-", with: "") }
            .sorted()
    }

    func downloadURL(forModelID modelID: String) -> URL? {
        guard downloadableModelIDs.contains(modelID) else { return nil }
        return URL(string: "\(Self.urlBase)-\(modelID).bin")
    }

    func localFileURL(forModelID modelID: String) async -> URL? {
        guard let dir = baseURL else { return nil }
        let file = dir.appendingPathComponent("ggml-\(modelID).bin")
        var isDir: ObjCBool = false
        return (fileManager.fileExists(atPath: file.path, isDirectory: &isDir) && !isDir.boolValue) ? file : nil
    }
}

enum WhisperModelStoreError: Error {
    case applicationSupportUnavailable
}
