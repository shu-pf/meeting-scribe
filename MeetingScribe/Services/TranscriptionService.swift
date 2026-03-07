//
//  TranscriptionService.swift
//  MeetingScribe
//
//  同梱 Whisper CLI 仕様: docs/WHISPER_CLI.md
//  起動パス: Bundle.main/Contents/Resources/whisper
//  引数: -m <モデル.bin> -f <入力WAV> -otxt -l auto
//  出力: 標準出力にテキスト
//

import Foundation

protocol TranscriptionServiceProtocol: Sendable {
    func transcribe(audioOrVideoURL: URL, modelID: String) async throws -> String
}

final class TranscriptionService: TranscriptionServiceProtocol {
    private let store: WhisperModelStoreProtocol
    private let processTimeout: TimeInterval = 600

    init(store: WhisperModelStoreProtocol = WhisperModelStore.shared) {
        self.store = store
    }

    func transcribe(audioOrVideoURL: URL, modelID: String) async throws -> String {
        try Task.checkCancellation()

        let modelURL = await store.localFileURL(forModelID: modelID)
        guard let modelPath = modelURL?.path, FileManager.default.fileExists(atPath: modelPath) else {
            throw TranscriptionError.modelNotFound(modelID)
        }

        let whisperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/whisper")
        guard FileManager.default.fileExists(atPath: whisperURL.path) else {
            throw TranscriptionError.whisperBinaryNotFound
        }

        let wavURL: URL
        if audioOrVideoURL.pathExtension.lowercased() == "wav" {
            wavURL = audioOrVideoURL
        } else {
            wavURL = try await AudioExtractor.extractWAV(from: audioOrVideoURL)
            defer { try? FileManager.default.removeItem(at: wavURL) }
        }

        try Task.checkCancellation()

        let process = Process()
        process.executableURL = whisperURL
        process.arguments = [
            "-m", modelPath,
            "-f", wavURL.path,
            "-otxt",
            "-l", "auto",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()

        let result: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
            let lock = NSLock()
            var resumed = false
            func resumeOnce(with r: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                switch r {
                case .success(let s): cont.resume(returning: s)
                case .failure(let e): cont.resume(throwing: e)
                }
            }

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0 {
                    resumeOnce(with: .success(text))
                } else {
                    resumeOnce(with: .failure(TranscriptionError.processFailed(exitCode: Int(process.terminationStatus))))
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(processTimeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
                resumeOnce(with: .failure(TranscriptionError.timeout))
            }
        }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        try Task.checkCancellation()
        return result
    }
}

enum TranscriptionError: Error {
    case modelNotFound(String)
    case whisperBinaryNotFound
    case outputEncodingFailed
    case timeout
    case processFailed(exitCode: Int)
}
