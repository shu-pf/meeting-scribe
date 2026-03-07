//
//  WhisperModelDownloader.swift
//  MeetingScribe
//

import Foundation

/// 指定モデルを Application Support 配下にダウンロードする。進捗とキャンセルに対応。
final class WhisperModelDownloader: NSObject, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var destinationURL: URL?
    private var observation: NSKeyValueObservation?
    private weak var downloadTask: URLSessionDownloadTask?

    func download(
        modelID: String,
        store: WhisperModelStoreProtocol,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws {
        guard let url = store.downloadURL(forModelID: modelID) else {
            throw WhisperModelDownloadError.unsupportedModel(modelID)
        }
        let directoryURL = try store.modelsDirectoryURL()
        let dest = directoryURL.appendingPathComponent("ggml-\(modelID).bin")

        if FileManager.default.fileExists(atPath: dest.path) {
            progressHandler(1.0)
            return
        }

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.progressHandler = progressHandler
        self.destinationURL = dest
        let task = session.downloadTask(with: url)
        downloadTask = task

        observation = task.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
            DispatchQueue.main.async {
                progressHandler(progress.fractionCompleted)
            }
        }

        task.resume()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
        }

        observation?.invalidate()
        observation = nil
    }

    func cancel() {
        downloadTask?.cancel()
    }
}

extension WhisperModelDownloader: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let dest = destinationURL else {
            continuation?.resume(throwing: WhisperModelDownloadError.downloadFailed)
            continuation = nil
            return
        }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            progressHandler?(1.0)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        destinationURL = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            destinationURL = nil
        }
    }
}

enum WhisperModelDownloadError: Error {
    case unsupportedModel(String)
    case downloadFailed
}
